import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/discovery.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/eventbus/basic.dart' as p2p_event_bus;
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_mgr;
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_udx/dart_udx.dart';
import 'package:test/test.dart';

import '../real_net_stack.dart';
import 'message_propagation_test.dart' show MockHost, MockNetwork, TestNetworkManager;

/// A discovery service shared by the nodes of a test: what one advertises,
/// the others find.
class _MemoryDiscovery implements Discovery {
  final Map<String, Map<PeerId, AddrInfo>> _ads;
  final AddrInfo Function() _self;
  final Duration ttl;
  final advertised = <String>[];
  final searched = <String>[];

  _MemoryDiscovery(this._ads, this._self, {this.ttl = const Duration(hours: 1)});

  @override
  Future<Duration> advertise(String ns, [List<DiscoveryOption> options = const []]) async {
    advertised.add(ns);
    final self = _self();
    _ads.putIfAbsent(ns, () => {})[self.id] = self;
    return ttl;
  }

  @override
  Future<Stream<AddrInfo>> findPeers(String ns, [List<DiscoveryOption> options = const []]) async {
    searched.add(ns);
    final self = _self().id;
    return Stream.fromIterable([...?_ads[ns]?.values.where((p) => p.id != self)]);
  }
}

/// Waits until [condition] is true, checking every 50 ms, for at most [timeout].
Future<void> _until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 10), required String reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting: $reason');
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  const topic = 'discovered';

  group('Discovery, as go-libp2p-pubsub', () {
    late PubSub pubsub;
    late _MemoryDiscovery discovery;

    setUp(() async {
      final manager = TestNetworkManager();
      final keyPair = await generateEd25519KeyPair();
      final peerId = PeerId.fromPublicKey(keyPair.publicKey);
      final host = MockHost(peerId, keyPair.privateKey);
      (host.network as MockNetwork).manager = manager;
      manager.registerNetwork(peerId, host.network as MockNetwork);
      discovery = _MemoryDiscovery({}, () => AddrInfo(peerId, const []), ttl: const Duration(milliseconds: 200));
      pubsub = PubSub(host, GossipSubRouter(), privateKey: keyPair.privateKey, discovery: discovery);
    });

    tearDown(() => pubsub.stop());

    test('advertises a subscribed topic under floodsub:<topic>, again when the advertisement expires', () async {
      await pubsub.start();
      final subscription = pubsub.subscribe(topic);
      pubsub.subscribe(topic); // A second subscription does not advertise again.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(discovery.advertised, ['floodsub:$topic']);

      await Future.delayed(const Duration(milliseconds: 250));
      expect(discovery.advertised, ['floodsub:$topic', 'floodsub:$topic']);

      await pubsub.unsubscribe(topic);
      expect(subscription.isCancelled, isTrue);
      discovery.advertised.clear();
      await Future.delayed(const Duration(milliseconds: 300));
      expect(discovery.advertised, isEmpty);
    });

    test('topics subscribed before start are advertised on start', () async {
      pubsub.subscribe(topic);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(discovery.advertised, isEmpty);
      await pubsub.start();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(discovery.advertised, ['floodsub:$topic']);
    });

    test('searches for the peers of a subscribed topic without enough peers, every poll', () async {
      await pubsub.start();
      pubsub.subscribe(topic);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(discovery.searched, contains('floodsub:$topic'));

      final before = discovery.searched.length;
      await Future.delayed(discoveryPollInterval * 2.5);
      expect(discovery.searched.length, greaterThanOrEqualTo(before + 2));
    });

    test('stop ends advertising and searching', () async {
      await pubsub.start();
      pubsub.subscribe(topic);
      await Future.delayed(const Duration(milliseconds: 50));
      await pubsub.stop();
      discovery.advertised.clear();
      discovery.searched.clear();
      await Future.delayed(discoveryPollInterval * 1.5);
      expect(discovery.advertised, isEmpty);
      expect(discovery.searched, isEmpty);
    });

    test('publish with ready waits for the topic to be ready, or times out without publishing', () async {
      await pubsub.start();
      await expectLater(
        pubsub.publish(topic, Uint8List.fromList([1]),
            ready: minTopicSize(1), readyTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
      );
      expect(discovery.searched, contains('floodsub:$topic'));

      var ready = false;
      final published = pubsub.publish(topic, Uint8List.fromList([2]), ready: (router, t) => ready);
      await Future.delayed(const Duration(milliseconds: 200));
      ready = true;
      await published.timeout(const Duration(seconds: 1));
    });
  });

  group('Discovery on a real network', () {
    final nodes = <({Host host, PubSub pubsub, GossipSubRouter router})>[];
    final ads = <String, Map<PeerId, AddrInfo>>{};

    Future<({Host host, PubSub pubsub, GossipSubRouter router})> node() async {
      final n = await createLibp2pNode(
        udxInstance: UDX(),
        resourceManager: NullResourceManager(),
        connManager: p2p_conn_mgr.ConnectionManager(),
        hostEventBus: p2p_event_bus.BasicBus(),
      );
      final router = GossipSubRouter();
      final pubsub = PubSub(n.host, router,
          privateKey: n.keyPair.privateKey,
          discovery: _MemoryDiscovery(ads, () => AddrInfo(n.host.id, n.host.addrs)));
      await pubsub.start();
      final created = (host: n.host as Host, pubsub: pubsub, router: router);
      nodes.add(created);
      return created;
    }

    tearDown(() async {
      for (final n in nodes) {
        await n.pubsub.stop();
        await n.host.close();
      }
      nodes.clear();
      ads.clear();
    });

    test('nodes that share a topic find each other, connect, and deliver messages', () async {
      final a = await node();
      final b = await node();
      expect(a.host.network.peers, isEmpty);

      final received = Completer<PubSubMessage>();
      a.pubsub.subscribe(topic).stream.listen((m) {
        if (!received.isCompleted) received.complete(m as PubSubMessage);
      });
      b.pubsub.subscribe(topic);

      await _until(() => b.router.mesh[topic]?.contains(a.host.id) ?? false,
          reason: 'B to find, connect to and GRAFT A');

      await b.pubsub.publish(topic, Uint8List.fromList('found you'.codeUnits), ready: minTopicSize(1));
      final message = await received.future.timeout(const Duration(seconds: 10));
      expect(String.fromCharCodes(message.data), 'found you');
    });
  });
}

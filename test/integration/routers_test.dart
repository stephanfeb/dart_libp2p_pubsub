import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:test/test.dart';

import 'message_propagation_test.dart' show MockHost, MockNetwork, TestNetworkManager;

class _Node {
  final MockHost host;
  final PubSub pubsub;
  final Router router;
  final List<PubSubMessage> received = [];
  _Node(this.host, this.pubsub, this.router);
  PeerId get id => host.id;
}

void main() {
  const topic = 'routers';
  late TestNetworkManager manager;
  final nodes = <_Node>[];

  setUp(() {
    manager = TestNetworkManager();
    nodes.clear();
  });

  tearDown(() async {
    for (final n in nodes) {
      await n.pubsub.stop();
    }
  });

  Future<_Node> node(Router router) async {
    final keyPair = await generateEd25519KeyPair();
    final peerId = PeerId.fromPublicKey(keyPair.publicKey);
    final host = MockHost(peerId, keyPair.privateKey);
    (host.network as MockNetwork).manager = manager;
    manager.registerNetwork(peerId, host.network as MockNetwork);
    final pubsub = PubSub(host, router, privateKey: keyPair.privateKey);
    final n = _Node(host, pubsub, router);
    nodes.add(n);
    return n;
  }

  Future<void> startAll() async {
    for (final n in nodes) {
      await n.pubsub.start();
    }
    for (final n in nodes) {
      n.pubsub.subscribe(topic).stream.listen((m) => n.received.add(m as PubSubMessage));
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> publish(_Node n, String text) async {
    await n.pubsub.publish(topic, Uint8List.fromList(text.codeUnits));
    await Future.delayed(const Duration(milliseconds: 300));
  }

  test('GossipSub and FloodSub nodes exchange messages over /floodsub/1.0.0', () async {
    final g = await node(GossipSubRouter());
    final f = await node(FloodSubRouter());
    await startAll();

    expect(f.pubsub.comms.protocolOf(g.id), floodSubID);
    expect(g.pubsub.comms.protocolOf(f.id), floodSubID);

    await publish(g, 'from gossipsub');
    await publish(f, 'from floodsub');

    expect(f.received.map((m) => String.fromCharCodes(m.data)), ['from gossipsub', 'from floodsub']);
    expect(g.received.map((m) => String.fromCharCodes(m.data)), ['from gossipsub', 'from floodsub']);
  });

  test('two GossipSub nodes negotiate /meshsub/1.3.0', () async {
    final a = await node(GossipSubRouter());
    final b = await node(GossipSubRouter());
    await startAll();
    expect(a.pubsub.comms.protocolOf(b.id), gossipSubIDv13);
    expect(a.router is GossipSubRouter && (a.router as GossipSubRouter).extensions.of(b.id) != null, isTrue,
        reason: 'B sent its first RPC');
  });

  test('GossipSub v1.3: peers with the test extension exchange TestExtension messages, as go-libp2p-pubsub', () async {
    final got = <String, List<PeerId>>{'a': [], 'b': [], 'c': []};
    final a = await node(GossipSubRouter(
        testExtension: TestExtensionConfig(onReceiveTestExtension: (p) => got['a']!.add(p))));
    final b = await node(GossipSubRouter(
        testExtension: TestExtensionConfig(onReceiveTestExtension: (p) => got['b']!.add(p))));
    final c = await node(GossipSubRouter()); // Without the extension.
    await startAll();
    expect(got['a'], [b.id]);
    expect(got['b'], [a.id]);
    final ra = a.router as GossipSubRouter;
    expect(ra.extensions.of(b.id)?.testExtension, isTrue);
    expect(ra.extensions.of(c.id)?.testExtension, isFalse);
  });

  test('GossipSub v1.3: a peer that announces its extensions twice is penalised, as go-libp2p-pubsub', () async {
    final a = await node(GossipSubRouter(
      scoreParams: const PeerScoreParams(behaviourPenaltyWeight: -1, behaviourPenaltyDecay: 0.99),
      scoreThresholds: const PeerScoreThresholds(gossipThreshold: -10, publishThreshold: -50, graylistThreshold: -80),
    ));
    final b = await node(GossipSubRouter());
    await startAll();
    final ra = a.router as GossipSubRouter;
    expect(ra.extensions.of(b.id), isNotNull);
    expect(ra.score!.snapshot(b.id)!.behaviourPenalty, 0);
    await ra.handleRpc(b.id, pb.RPC()..ensureControl().extensions = pb.ControlExtensions());
    expect(ra.score!.snapshot(b.id)!.behaviourPenalty, 10);
  });

  test('FloodSub does not loop messages in a cycle, and each node gets each message once', () async {
    for (var i = 0; i < 4; i++) {
      await node(FloodSubRouter());
    }
    await startAll();

    await publish(nodes[0], 'once');

    for (final n in nodes) {
      expect(n.received.map((m) => String.fromCharCodes(m.data)), ['once'], reason: '${n.id}');
    }
  });

  test('FloodSub validates messages: a rejected message is not delivered or forwarded', () async {
    final a = await node(FloodSubRouter());
    final b = await node(FloodSubRouter());
    final c = await node(FloodSubRouter());
    await startAll();
    b.pubsub.registerTopicValidator(topic, (from, msg) => ValidationResult.reject);
    c.pubsub.registerTopicValidator(topic, (from, msg) => ValidationResult.reject);

    await publish(a, 'bad');

    expect(b.received, isEmpty);
    expect(c.received, isEmpty);
  });

  group('RandomSub peer selection, as go-libp2p-pubsub', () {
    Future<List<PeerId>> distinct(int n) async => [for (var i = 0; i < n; i++) await PeerId.random()];

    test('all peers when there are at most RandomSubD', () async {
      final r = RandomSubRouter(networkSize: 1000);
      final candidates = await distinct(randomSubD);
      expect(r.selectPeers(topic, candidates), unorderedEquals(candidates));
    });

    test('max(RandomSubD, sqrt(size)) RandomSub peers, plus every FloodSub peer', () async {
      final r = RandomSubRouter(networkSize: 100, random: Random(1));
      final random = await distinct(20);
      final flood = await distinct(2);
      for (final p in random) {
        await r.addPeer(p, randomSubID);
      }
      for (final p in flood) {
        await r.addPeer(p, floodSubID);
      }
      final selected = r.selectPeers(topic, [...random, ...flood]).toList();
      expect(selected, containsAll(flood));
      expect(selected.where(random.contains), hasLength(10)); // sqrt(100) > 6.

      final small = RandomSubRouter(networkSize: 4);
      expect(small.selectPeers(topic, random), hasLength(randomSubD));
    });
  });

  group('stop and start', () {
    for (final (name, make) in [
      ('GossipSub', () => GossipSubRouter() as Router),
      ('FloodSub', () => FloodSubRouter() as Router),
    ]) {
      test('a $name node stopped leaves the network and rejoins it when started again', () async {
        final a = await node(make());
        final b = await node(make());
        await startAll();
        List<String> texts(_Node n) => n.received.map((m) => String.fromCharCodes(m.data)).toList();

        await publish(a, 'before');
        expect(texts(b), ['before']);

        await b.pubsub.stop().timeout(const Duration(seconds: 5));
        if (b.router case final GossipSubRouter r) expect(r.mesh, isEmpty);
        await publish(a, 'while stopped');
        expect(texts(b), ['before']);

        await b.pubsub.start();
        await Future.delayed(const Duration(milliseconds: 300));
        if (b.router case final GossipSubRouter r) expect(r.mesh[topic], {a.id});
        await publish(a, 'after restart');
        await publish(b, 'from b');

        expect(texts(b), ['before', 'after restart', 'from b']);
        expect(texts(a), ['before', 'while stopped', 'after restart', 'from b']);
      });
    }
  });

  test('blacklisting a connected peer drops it and its messages', () async {
    final a = await node(GossipSubRouter());
    final b = await node(GossipSubRouter());
    await startAll();
    List<String> texts(_Node n) => n.received.map((m) => String.fromCharCodes(m.data)).toList();

    b.pubsub.blacklistPeer(a.id);
    await Future.delayed(const Duration(milliseconds: 50));
    expect((b.router as GossipSubRouter).mesh[topic], isEmpty);

    await publish(a, 'from a');
    await publish(b, 'from b');
    expect(texts(b), ['from b']);
    expect(texts(a), ['from a'], reason: 'b no longer sends to a');
  });

  test('enoughPeers counts the topic peers, against the router default when 0, as go-libp2p-pubsub', () async {
    final f = await node(FloodSubRouter());
    final r = await node(RandomSubRouter(networkSize: 10));
    final g = await node(GossipSubRouter());
    await startAll();

    for (final n in [f, r, g]) {
      expect(n.router.enoughPeers('other', 1), isFalse, reason: '${n.router}: no peer on the topic');
      expect(n.router.enoughPeers(topic, 2), isTrue, reason: '${n.router}: two peers on the topic');
      expect(n.router.enoughPeers(topic, 3), isFalse, reason: '${n.router}');
    }
    // Defaults: FloodSubTopicSearchSize (5), RandomSubD (6), DLow (6).
    for (final n in [f, r, g]) {
      expect(n.router.enoughPeers(topic, 0), isFalse, reason: '${n.router}');
    }
  });

  test('setTopicScoreParams scores a topic set after the router is created, as go-libp2p-pubsub Topic.SetScoreParams', () async {
    expect(() => GossipSubRouter().setTopicScoreParams(topic, const TopicScoreParams(topicWeight: 1)),
        throwsStateError, reason: 'scoring disabled');

    final router = GossipSubRouter(
      scoreParams: const PeerScoreParams(),
      scoreThresholds: const PeerScoreThresholds(gossipThreshold: -10, publishThreshold: -50, graylistThreshold: -80),
    );
    // Before the router is attached, and after.
    router.setTopicScoreParams('early', const TopicScoreParams(topicWeight: 1));
    await node(router);
    await startAll();
    router.setTopicScoreParams(topic, const TopicScoreParams(
      topicWeight: 1,
      invalidMessageDeliveriesWeight: -1,
      invalidMessageDeliveriesDecay: 0.5,
    ));
    expect(router.score!.topicScoreParams('early'), isNotNull);
    expect(router.score!.topicScoreParams(topic)!.invalidMessageDeliveriesWeight, -1);
    expect(() => router.setTopicScoreParams(topic, const TopicScoreParams(topicWeight: -1)), throwsArgumentError);
  });

  test('PubSub takes the per-peer outbound queue size, as go-libp2p-pubsub WithPeerOutboundQueueSize', () async {
    final keyPair = await generateEd25519KeyPair();
    final host = MockHost(PeerId.fromPublicKey(keyPair.publicKey), keyPair.privateKey);
    expect(PubSub(host, GossipSubRouter(), privateKey: keyPair.privateKey).peerOutboundQueueSize,
        defaultPeerOutboundQueueSize);
    expect(PubSub(host, FloodSubRouter(), privateKey: keyPair.privateKey, peerOutboundQueueSize: 256)
        .peerOutboundQueueSize, 256);
    expect(() => PubSub(host, GossipSubRouter(), privateKey: keyPair.privateKey, peerOutboundQueueSize: 0),
        throwsArgumentError);
  });
}

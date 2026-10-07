import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
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

  test('two GossipSub nodes negotiate /meshsub/1.2.0', () async {
    final a = await node(GossipSubRouter());
    final b = await node(GossipSubRouter());
    await startAll();
    expect(a.pubsub.comms.protocolOf(b.id), gossipSubIDv12);
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
}

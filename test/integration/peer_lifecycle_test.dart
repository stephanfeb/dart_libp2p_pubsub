import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

/// A node on the real network stack, with PubSub and a GossipSubRouter.
class _Node {
  final Host host;
  final PubSub pubsub;
  final GossipSubRouter router;

  _Node(this.host, this.pubsub, this.router);

  PeerId get id => host.id;

  static Future<_Node> start() async {
    final node = await createLibp2pNode(
      udxInstance: UDX(),
      resourceManager: NullResourceManager(),
      connManager: p2p_conn_mgr.ConnectionManager(),
      hostEventBus: p2p_event_bus.BasicBus(),
    );
    final router = GossipSubRouter();
    final pubsub = PubSub(node.host, router, privateKey: node.keyPair.privateKey);
    await pubsub.start();
    return _Node(node.host, pubsub, router);
  }

  Future<void> connect(_Node other) => host.connect(AddrInfo(other.id, other.host.addrs));

  Future<void> stop() async {
    await pubsub.stop();
    await host.close();
  }
}

/// Waits until [condition] is true, checking every 100 ms, for at most [timeout].
Future<void> _until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 10), required String reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting: $reason');
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  const topic = 'peer-lifecycle-topic';
  late _Node a;
  late _Node b;

  setUp(() async {
    a = await _Node.start();
    b = await _Node.start();
  });

  tearDown(() async {
    await a.stop();
    await b.stop();
  });

  test('nodes that subscribe before they connect build a mesh and deliver messages', () async {
    final received = Completer<PubSubMessage>();
    a.pubsub.subscribe(topic).stream.listen((m) {
      if (!received.isCompleted) received.complete(m as PubSubMessage);
    });
    b.pubsub.subscribe(topic);

    await a.connect(b);

    await _until(() => a.router.mesh[topic]?.contains(b.id) ?? false,
        reason: 'A to GRAFT B');
    await _until(() => b.router.mesh[topic]?.contains(a.id) ?? false,
        reason: 'B to GRAFT A');

    await b.pubsub.publish(topic, Uint8List.fromList(utf8.encode('hello')));
    final message = await received.future.timeout(const Duration(seconds: 10));
    expect(utf8.decode(message.data), equals('hello'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a peer that disconnects leaves the mesh and keeps its score', () async {
    a.pubsub.subscribe(topic);
    b.pubsub.subscribe(topic);
    await a.connect(b);
    await _until(() => a.router.mesh[topic]?.contains(b.id) ?? false,
        reason: 'A to GRAFT B');

    final scoreOfB = a.pubsub.getPeerScoreObject(b.id);

    await a.host.network.closePeer(b.id);

    await _until(() => !(a.router.mesh[topic]?.contains(b.id) ?? false),
        reason: 'A to remove B from its mesh');
    // The score is kept, so B cannot clear its penalties by reconnecting.
    expect(a.pubsub.peerScores[b.id], same(scoreOfB));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

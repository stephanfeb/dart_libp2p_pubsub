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

/// A subscriber must stay in, or come back to, the mesh of a peer after its
/// connection or its stream to the peer is lost, as against Teranode's
/// go-libp2p-pubsub nodes, which trim connections (dart-libp2p-cce.4).
class _Node {
  final Host host;
  final PubSub pubsub;
  final GossipSubRouter router;
  final received = <String>[];

  _Node(this.host, this.pubsub, this.router);

  PeerId get id => host.id;

  static Future<_Node> start(String topic) async {
    final node = await createLibp2pNode(
      udxInstance: UDX(),
      resourceManager: NullResourceManager(),
      connManager: p2p_conn_mgr.ConnectionManager(),
      hostEventBus: p2p_event_bus.BasicBus(),
    );
    final router = GossipSubRouter();
    final pubsub = PubSub(node.host, router, privateKey: node.keyPair.privateKey);
    await pubsub.start();
    final n = _Node(node.host, pubsub, router);
    pubsub.subscribe(topic).stream.listen((m) {
      n.received.add(utf8.decode((m as PubSubMessage).data));
    });
    return n;
  }

  Future<void> connect(_Node other) => host.connect(AddrInfo(other.id, other.host.addrs));

  bool meshes(String topic, _Node other) => router.mesh[topic]?.contains(other.id) ?? false;

  Future<void> stop() async {
    await pubsub.stop();
    await host.close();
  }
}

Future<void> _until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 15), required String reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting: $reason');
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  const topic = 'mesh-rejoin-topic';
  late _Node a;
  late _Node b;
  var sent = 0;

  setUp(() async {
    a = await _Node.start(topic);
    b = await _Node.start(topic);
  });

  tearDown(() async {
    await a.stop();
    await b.stop();
  });

  /// Publishes from [from] until [to] receives one of the messages: the
  /// first message after a rejoin can race the GRAFT.
  Future<void> delivers(_Node from, _Node to, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      final text = 'm${sent++}';
      await from.pubsub.publish(topic, Uint8List.fromList(utf8.encode(text)));
      final until = DateTime.now().add(const Duration(seconds: 1));
      while (DateTime.now().isBefore(until)) {
        if (to.received.contains(text)) return;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (DateTime.now().isAfter(deadline)) fail('No delivery: $reason');
    }
  }

  Future<void> meshed(String reason) async {
    await _until(() => a.meshes(topic, b) && b.meshes(topic, a), reason: reason);
  }

  test('after the remote closes the connection and we dial again, '
      'both sides mesh again and deliver', () async {
    await a.connect(b);
    await meshed('first mesh');

    // As a go-libp2p connection manager trims: the remote closes.
    await b.host.network.closePeer(a.id);
    await _until(() => !a.meshes(topic, b), reason: 'A to drop B');

    await a.connect(b);
    await meshed('mesh after redial');
    await delivers(b, a, 'B to A after redial');
    await delivers(a, b, 'A to B after redial');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('repeated trims do not end the rejoining', () async {
    await a.connect(b);
    await meshed('first mesh');

    // More than the dead-peer backoff's 4 attempts in 10 minutes.
    for (var i = 0; i < 6; i++) {
      await b.host.network.closePeer(a.id);
      await _until(() => !a.meshes(topic, b), reason: 'A to drop B (trim $i)');
      await a.connect(b);
      await meshed('mesh after trim $i');
    }
    await delivers(b, a, 'B to A after the trims');
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('when our stream to a peer stops taking writes but the connection '
      'stays, we greet the peer on a new stream and mesh again', () async {
    await a.connect(b);
    await meshed('first mesh');

    // Half close A's stream to B. Its reads stay open, so the watcher does
    // not see it end; only the next write finds it unusable.
    final stream = a.pubsub.comms.outboundStreamForTesting(b.id)!;
    await stream.closeWrite();

    // The next RPC from A finds the stream unusable. A must drop B from its
    // router, greet it on a new stream and GRAFT it again.
    await delivers(a, b, 'A to B on a new stream');
    expect(a.pubsub.comms.outboundStreamForTesting(b.id), isNot(same(stream)));
    await meshed('mesh after the new stream');
    await delivers(b, a, 'B to A');
  }, timeout: const Timeout(Duration(seconds: 90)));
}

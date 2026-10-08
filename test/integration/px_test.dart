import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/network.dart' show Connectedness;
import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/eventbus/basic.dart' as p2p_event_bus;
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_mgr;
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_udx/dart_udx.dart';
import 'package:test/test.dart';

import '../real_net_stack.dart';

class _Node {
  final Host host;
  final PubSub pubsub;
  final GossipSubRouter router;
  final List<PubSubMessage> received = [];

  _Node(this.host, this.pubsub, this.router);

  PeerId get id => host.id;

  static Future<_Node> start({bool doPX = false}) async {
    final n = await createLibp2pNode(
      udxInstance: UDX(),
      resourceManager: NullResourceManager(),
      connManager: p2p_conn_mgr.ConnectionManager(),
      hostEventBus: p2p_event_bus.BasicBus(),
    );
    final router = GossipSubRouter(doPX: doPX);
    final pubsub = PubSub(n.host, router, privateKey: n.keyPair.privateKey);
    await pubsub.start();
    return _Node(n.host, pubsub, router);
  }

  Future<void> connect(_Node other) => host.connect(AddrInfo(other.id, other.host.addrs));

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
  const topic = 'px-topic';

  test('peers pruned with Peer Exchange connect to each other and build a mesh, on a real network', () async {
    final bootstrapper = await _Node.start(doPX: true);
    final b = await _Node.start();
    final c = await _Node.start();
    addTearDown(() async {
      for (final n in [bootstrapper, b, c]) {
        await n.stop();
      }
    });

    for (final n in [bootstrapper, b, c]) {
      n.pubsub.subscribe(topic).stream.listen((m) => n.received.add(m as PubSubMessage));
    }
    await bootstrapper.connect(b);
    await bootstrapper.connect(c);
    await _until(() => bootstrapper.router.mesh[topic]?.containsAll([b.id, c.id]) ?? false,
        reason: 'the bootstrapper to mesh with B and C');
    expect(b.host.network.connectedness(c.id), isNot(Connectedness.connected));
    // As go-libp2p-pubsub, the router stores the signed peer records that
    // identify received, to offer them in PX.
    for (final peer in [b, c]) {
      expect(await bootstrapper.router.certifiedAddrBook.getPeerRecord(peer.id), isNotNull,
          reason: 'the record identify received from $peer');
    }

    // The bootstrapper leaves the topic: its PRUNEs offer B to C and C to B.
    await bootstrapper.pubsub.unsubscribe(topic);

    await _until(() => b.host.network.connectedness(c.id) == Connectedness.connected,
        reason: 'B and C to connect through PX');
    await _until(() => (b.router.mesh[topic]?.contains(c.id) ?? false) && (c.router.mesh[topic]?.contains(b.id) ?? false),
        reason: 'B and C to mesh with each other');

    await b.pubsub.publish(topic, Uint8List.fromList('via px'.codeUnits));
    await _until(() => c.received.any((m) => String.fromCharCodes(m.data) == 'via px'),
        reason: 'C to receive the message of B');
  });
}

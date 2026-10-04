import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/p2p/host/eventbus/basic.dart' as p2p_event_bus;
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_mgr;
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p_pubsub/src/core/sign.dart';
import 'package:dart_udx/dart_udx.dart';
import 'package:test/test.dart';

import '../real_net_stack.dart';

// GitHub dart_libp2p_pubsub#2: a PubSub created without a privateKey sent
// unsigned messages, which its own strict signature policy then rejected.
// go-libp2p-pubsub signs with the host's key from the peerstore by default.
void main() {
  group('PubSub without an explicit privateKey', () {
    late Libp2pNode a;
    late Libp2pNode b;
    late PubSub pubsubA;
    late PubSub pubsubB;

    Future<Libp2pNode> node() => createLibp2pNode(
          udxInstance: UDX(),
          resourceManager: NullResourceManager(),
          connManager: p2p_conn_mgr.ConnectionManager(),
          hostEventBus: p2p_event_bus.BasicBus(),
        );

    setUp(() async {
      a = await node();
      b = await node();
      pubsubA = PubSub(a.host, GossipSubRouter());
      pubsubB = PubSub(b.host, GossipSubRouter());
      await pubsubA.start();
      await pubsubB.start();
      await a.host.connect(AddrInfo(b.peerId, b.host.addrs));
    });

    tearDown(() async {
      await pubsubA.stop();
      await pubsubB.stop();
      await a.host.close();
      await b.host.close();
    });

    test('signs with the host key, and peers accept the message', () async {
      const topic = 'default-signing-key';
      final payload = Uint8List.fromList(utf8.encode('signed by default'));
      final received = Completer<PubSubMessage>();

      final sub = pubsubB.subscribe(topic);
      final listener = sub.stream.listen((m) {
        if (m is PubSubMessage && m.from == a.peerId && !received.isCompleted) {
          received.complete(m);
        }
      });
      pubsubA.subscribe(topic);
      await Future.delayed(const Duration(seconds: 3));

      await pubsubA.publish(topic, payload);
      final message = await received.future.timeout(const Duration(seconds: 15));
      await listener.cancel();

      expect(message.data, payload);
      expect(message.rpcMessage.signature, isNotEmpty);
      expect(await verifyMessageSignature(message), isTrue);
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}

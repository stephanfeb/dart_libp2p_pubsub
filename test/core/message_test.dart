import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/message.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as rpc_pb;

void main() {
  group('PubSubMessage Tests', () {
    late PeerId originPeerId;
    late PeerId receivedFromPeerId;
    late rpc_pb.Message pbMessage;
    late PubSubMessage pubSubMessageWithReceiver;
    late PubSubMessage pubSubMessageLocal;

    setUp(() { // Changed to synchronous setUp
      // Using fixed PeerIds for deterministic tests
      originPeerId = PeerId.fromString('QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N'); // Example valid PeerId
      receivedFromPeerId = PeerId.fromString('QmQZE61dnA2a7wD9f4zGjZ7G9zX2X5Y4C9x1XQ8x8JzYdE'); // Another example valid PeerId

      pbMessage = rpc_pb.Message();
      pbMessage.from = originPeerId.toBytes();
      pbMessage.data = Uint8List.fromList([1, 2, 3, 4, 5]);
      pbMessage.topic = 'test-topic'; // Assuming 'topic' field exists and is used
      pbMessage.seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1]);
      pbMessage.signature = Uint8List.fromList([6, 7, 8]);
      pbMessage.key = Uint8List.fromList([9, 10, 11]);

      pubSubMessageWithReceiver = PubSubMessage(
        rpcMessage: pbMessage,
        receivedFrom: receivedFromPeerId,
      );

      pubSubMessageLocal = PubSubMessage(
        rpcMessage: pbMessage,
        // receivedFrom is null for locally originated messages
      );
    });

    test('constructor and receivedFrom property', () {
      expect(pubSubMessageWithReceiver.rpcMessage, same(pbMessage));
      expect(pubSubMessageWithReceiver.receivedFrom, equals(receivedFromPeerId));
      expect(pubSubMessageLocal.receivedFrom, isNull);
    });

    test('topic property delegates to rpcMessage.topic', () {
      expect(pubSubMessageWithReceiver.topic, equals('test-topic'));
    });

    test('data property delegates to rpcMessage.data', () {
      expect(pubSubMessageWithReceiver.data, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
    });

    test('seqno property delegates to rpcMessage.seqno', () {
      expect(pubSubMessageWithReceiver.seqno, equals(Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1])));
    });

    test('from property correctly constructs PeerId from rpcMessage.from', () {
      expect(pubSubMessageWithReceiver.from.toBytes(), equals(originPeerId.toBytes()));
      expect(pubSubMessageWithReceiver.from, equals(originPeerId));
    });

    test('signature property delegates to rpcMessage.signature', () {
      expect(pubSubMessageWithReceiver.signature, equals(Uint8List.fromList([6, 7, 8])));
    });

    test('key property delegates to rpcMessage.key', () {
      expect(pubSubMessageWithReceiver.key, equals(Uint8List.fromList([9, 10, 11])));
    });
    
    test('toString() produces a non-empty string', () {
      expect(pubSubMessageWithReceiver.toString(), isNotEmpty);
      expect(pubSubMessageLocal.toString(), isNotEmpty);
      // More specific checks can be added if the format is stable and important
      expect(pubSubMessageWithReceiver.toString(), contains(originPeerId.toBase58()));
      expect(pubSubMessageWithReceiver.toString(), contains('topic: test-topic'));
      expect(pubSubMessageWithReceiver.toString(), contains(receivedFromPeerId.toBase58()));
      expect(pubSubMessageLocal.toString(), contains('receivedFrom: local'));
    });

    test('handles rpc_pb.Message with empty optional fields', () {
      final emptyPbMessage = rpc_pb.Message();
      // 'from' and 'topic' might be required or have defaults in practice,
      // but testing how PubSubMessage handles them if they could be empty from protobuf.
      // For 'from', PeerId.fromBytes would throw if 'from' is empty and not a valid PeerId.
      // Let's assume 'from' is always valid for a PubSubMessage to be constructed.
      emptyPbMessage.from = originPeerId.toBytes(); // Required for .from getter
      emptyPbMessage.topic = "default-topic"; // Required for .topic getter

      final msg = PubSubMessage(rpcMessage: emptyPbMessage);
      expect(msg.data, isEmpty);
      expect(msg.seqno, isEmpty);
      expect(msg.signature, isEmpty);
      expect(msg.key, isEmpty);
    });
  });
}

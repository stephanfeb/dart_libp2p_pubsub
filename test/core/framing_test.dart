import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/utils/varint.dart';
import 'package:dart_libp2p_pubsub/src/core/comm.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:dart_libp2p_pubsub/src/util/midgen.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../gossipsub/persistent_streams_test.mocks.dart';

pb.Message _message(int size, [int seq = 0]) => pb.Message()
  ..from = [1, 2, 3]
  ..seqno = [seq]
  ..topic = 't'
  ..data = Uint8List(size);

void main() {
  group('splitRpc', () {
    test('returns a small RPC unchanged', () {
      final rpc = pb.RPC()..publish.add(_message(10));
      expect(splitRpc(rpc, 1000), equals([rpc]));
    });

    test('splits published messages into RPCs under the limit', () {
      final rpc = pb.RPC()..publish.addAll(List.generate(10, (i) => _message(300, i)));
      final parts = splitRpc(rpc, 1000);
      expect(parts.length, greaterThan(1));
      for (final part in parts) {
        expect(part.writeToBuffer().length, lessThanOrEqualTo(1000));
      }
      expect(parts.expand((p) => p.publish).length, equals(10));
    });

    test('splits subscriptions and control IDs, keeping all of them', () {
      final rpc = pb.RPC()
        ..subscriptions.addAll(List.generate(50, (i) => pb.RPC_SubOpts()
          ..subscribe = true
          ..topicid = 'topic-$i'))
        ..control = (pb.ControlMessage()
          ..graft.add(pb.ControlGraft()..topicID = 'g')
          ..ihave.add(pb.ControlIHave()
            ..topicID = 'a'
            ..messageIDs.addAll(List.generate(100, (i) => 'have-$i'.codeUnits)))
          ..iwant.add(pb.ControlIWant()..messageIDs.addAll(List.generate(100, (i) => 'want-$i'.codeUnits))));
      final parts = splitRpc(rpc, 300);
      for (final part in parts) {
        expect(part.writeToBuffer().length, lessThanOrEqualTo(300));
      }
      expect(parts.expand((p) => p.subscriptions).length, equals(50));
      expect(parts.expand((p) => p.control.graft).length, equals(1));
      expect(parts.expand((p) => p.control.ihave).expand((i) => i.messageIDs).toList(),
          equals(List.generate(100, (i) => 'have-$i'.codeUnits)));
      expect(parts.expand((p) => p.control.iwant).expand((i) => i.messageIDs).length, equals(100));
    });

    test('returns an oversized message in an RPC of its own', () {
      final rpc = pb.RPC()..publish.addAll([_message(10, 1), _message(2000, 2), _message(10, 3)]);
      final parts = splitRpc(rpc, 1000);
      expect(parts.expand((p) => p.publish).length, equals(3));
      expect(parts.where((p) => p.writeToBuffer().length > 1000).single.publish.single.seqno, equals([2]));
    });
  });

  group('PubSubProtocol', () {
    late MockHost host;
    late MockPeerId peer;
    late Future<void> Function(P2PStream, PeerId) handler;

    setUp(() {
      host = MockHost();
      peer = MockPeerId();
      when(peer.toBase58()).thenReturn('QmPeer');
      when(host.setStreamHandler(any, any)).thenAnswer((invocation) {
        handler = invocation.positionalArguments[1] as Future<void> Function(P2PStream, PeerId);
      });
    });

    test('a failed stream open with no concurrent caller is not an uncaught error', () async {
      when(host.newStream(any, any, any)).thenAnswer((_) async => throw Exception('protocol not supported'));
      final comms = PubSubProtocol(host, (_, __) async {});
      // An uncaught async error would fail this test.
      await expectLater(comms.sendRpc(peer, pb.RPC()..subscriptions.add(pb.RPC_SubOpts()..topicid = 't'), gossipSubIDv11),
          throwsException);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('sendRpc refuses an RPC larger than maxMessageSize', () async {
      final stream = MockP2PStream();
      when(stream.protocol()).thenReturn(gossipSubIDv11);
      when(stream.id()).thenReturn('s');
      when(stream.isClosed).thenReturn(false);
      when(stream.isWritable).thenReturn(true);
      when(host.newStream(any, any, any)).thenAnswer((_) async => stream);
      final comms = PubSubProtocol(host, (_, __) async {}, maxMessageSize: 100);
      await expectLater(comms.sendRpc(peer, pb.RPC()..publish.add(_message(200)), gossipSubIDv11),
          throwsA(isA<RpcTooLargeException>()));
      verifyNever(stream.write(any));
    });

    test('an inbound frame larger than maxMessageSize resets the stream without reading it', () async {
      final received = <pb.RPC>[];
      PubSubProtocol(host, (_, rpc) async => received.add(rpc), maxMessageSize: 100);

      final stream = MockP2PStream();

      when(stream.protocol()).thenReturn(gossipSubIDv11);
      var closed = false;
      when(stream.id()).thenReturn('in');
      when(stream.protocol()).thenReturn(gossipSubIDv11);
      when(stream.isClosed).thenAnswer((_) => closed);
      when(stream.reset()).thenAnswer((_) async => closed = true);
      when(stream.close()).thenAnswer((_) async => closed = true);
      // A length prefix of 2^40 bytes, then data forever.
      final reads = [encodeVarint(1 << 40)];
      var bodyReads = 0;
      when(stream.read(any)).thenAnswer((_) async {
        if (reads.isNotEmpty) return reads.removeAt(0);
        bodyReads++;
        return Uint8List(1024);
      });

      await handler(stream, peer);
      expect(received, isEmpty);
      expect(bodyReads, equals(0));
      verify(stream.reset()).called(1);
    });

    test('writes on a stream do not overlap', () async {
      final stream = MockP2PStream();
      when(stream.protocol()).thenReturn(gossipSubIDv11);
      when(stream.id()).thenReturn('s');
      when(stream.isClosed).thenReturn(false);
      when(stream.isWritable).thenReturn(true);
      when(host.newStream(any, any, any)).thenAnswer((_) async => stream);
      final firstWrite = Completer<void>();
      final writes = <int>[];
      when(stream.write(any)).thenAnswer((invocation) {
        writes.add((invocation.positionalArguments[0] as Uint8List).length);
        return writes.length == 1 ? firstWrite.future : Future.value();
      });
      final comms = PubSubProtocol(host, (_, __) async {});

      final big = comms.sendRpc(peer, pb.RPC()..publish.add(_message(40000)), gossipSubIDv11);
      final small = comms.sendRpc(peer, pb.RPC()..subscriptions.add(pb.RPC_SubOpts()..topicid = 't'), gossipSubIDv11);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(writes, hasLength(1), reason: 'the second frame must wait for the first');

      firstWrite.complete();
      await Future.wait([big, small]);
      expect(writes, hasLength(2));
    });

    test('a slow RPC handler does not hold up the next RPCs of the peer', () async {
      final handled = <pb.RPC>[];
      final never = Completer<void>();
      PubSubProtocol(host, (_, rpc) {
        handled.add(rpc);
        return handled.length == 1 ? never.future : Future.value();
      });

      Uint8List frame(pb.RPC rpc) {
        final body = rpc.writeToBuffer();
        return Uint8List.fromList([...encodeVarint(body.length), ...body]);
      }

      final stream = MockP2PStream();

      when(stream.protocol()).thenReturn(gossipSubIDv11);
      var closed = false;
      when(stream.id()).thenReturn('in');
      when(stream.protocol()).thenReturn(gossipSubIDv11);
      when(stream.isClosed).thenAnswer((_) => closed);
      when(stream.close()).thenAnswer((_) async => closed = true);
      final reads = [
        frame(pb.RPC()..publish.add(_message(10))),
        frame(pb.RPC()..control = (pb.ControlMessage()..graft.add(pb.ControlGraft()..topicID = 't'))),
      ];
      when(stream.read(any)).thenAnswer((_) async => reads.isEmpty ? Uint8List(0) : reads.removeAt(0));

      await handler(stream, peer);
      expect(handled, hasLength(2));
      expect(handled[1].control.graft.single.topicID, 't');
    });
  });
}

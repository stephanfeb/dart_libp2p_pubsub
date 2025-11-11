import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/network/context.dart' as p2p_context;

import 'package:dart_libp2p_pubsub/src/core/comm.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;

import 'persistent_streams_test.mocks.dart';

@GenerateMocks([Host, P2PStream, PeerId])
void main() {
  group('PubSubProtocol Persistent Streams', () {
    late MockHost mockHost;
    late MockPeerId mockPeer1;
    late MockPeerId mockPeer2;
    late List<pb.RPC> receivedMessages;
    late PubSubProtocol protocol;

    setUp(() {
      mockHost = MockHost();
      mockPeer1 = MockPeerId();
      mockPeer2 = MockPeerId();
      receivedMessages = [];

      // Setup peer IDs
      when(mockPeer1.toBytes()).thenReturn(Uint8List.fromList([1, 0, 1]));
      when(mockPeer1.toBase58()).thenReturn('QmPeer1');
      
      when(mockPeer2.toBytes()).thenReturn(Uint8List.fromList([2, 0, 2]));
      when(mockPeer2.toBase58()).thenReturn('QmPeer2');

      // Initialize protocol
      protocol = PubSubProtocol(mockHost, (peerId, rpc) async {
        receivedMessages.add(rpc);
      });

      verify(mockHost.setStreamHandler(gossipSubIDv11, any)).called(1);
    });

    tearDown(() async {
      await protocol.close();
    });

    test('creates new persistent stream for first message to peer', () async {
      final mockStream = MockP2PStream();
      when(mockStream.id()).thenReturn('stream-1');
      when(mockStream.isClosed).thenReturn(false);
      when(mockStream.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream);

      final rpc = pb.RPC();
      await protocol.sendRpc(mockPeer1, rpc, gossipSubIDv11);

      // Verify stream was created
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(1);
      
      // Verify message was written
      verify(mockStream.write(any)).called(1);
      
      // Verify stream was NOT closed
      verifyNever(mockStream.close());
    });

    test('reuses existing stream for multiple messages to same peer', () async {
      final mockStream = MockP2PStream();
      when(mockStream.id()).thenReturn('stream-1');
      when(mockStream.isClosed).thenReturn(false);
      when(mockStream.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream);

      // Send 3 messages to the same peer
      for (int i = 0; i < 3; i++) {
        final rpc = pb.RPC()..subscriptions.add(
          pb.RPC_SubOpts()
            ..subscribe = true
            ..topicid = 'test-topic-$i'
        );
        await protocol.sendRpc(mockPeer1, rpc, gossipSubIDv11);
      }

      // Verify stream was created only once
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(1);
      
      // Verify all 3 messages were written to the same stream
      verify(mockStream.write(any)).called(3);
      
      // Verify stream was never closed during sending
      verifyNever(mockStream.close());
    });

    test('creates separate streams for different peers', () async {
      final mockStream1 = MockP2PStream();
      final mockStream2 = MockP2PStream();
      
      when(mockStream1.id()).thenReturn('stream-1');
      when(mockStream1.isClosed).thenReturn(false);
      when(mockStream1.write(any)).thenAnswer((_) async {});
      
      when(mockStream2.id()).thenReturn('stream-2');
      when(mockStream2.isClosed).thenReturn(false);
      when(mockStream2.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream1);
      when(mockHost.newStream(mockPeer2, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream2);

      // Send messages to different peers
      final rpc1 = pb.RPC();
      final rpc2 = pb.RPC();
      
      await protocol.sendRpc(mockPeer1, rpc1, gossipSubIDv11);
      await protocol.sendRpc(mockPeer2, rpc2, gossipSubIDv11);

      // Verify separate streams were created
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(1);
      verify(mockHost.newStream(mockPeer2, [gossipSubIDv11], any)).called(1);
      
      // Verify messages went to correct streams
      verify(mockStream1.write(any)).called(1);
      verify(mockStream2.write(any)).called(1);
    });

    test('recreates stream if existing stream is closed', () async {
      final mockStream1 = MockP2PStream();
      final mockStream2 = MockP2PStream();
      var streamCallCount = 0;
      
      when(mockStream1.id()).thenReturn('stream-1');
      when(mockStream1.isClosed).thenReturn(false); // Initially open
      when(mockStream1.write(any)).thenAnswer((_) async {});
      
      when(mockStream2.id()).thenReturn('stream-2');
      when(mockStream2.isClosed).thenReturn(false);
      when(mockStream2.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async {
            streamCallCount++;
            return streamCallCount == 1 ? mockStream1 : mockStream2;
          });

      // Send first message
      await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
      expect(streamCallCount, 1);

      // Mark stream as closed
      when(mockStream1.isClosed).thenReturn(true);

      // Send second message - should create new stream
      await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
      
      // Verify new stream was created
      expect(streamCallCount, 2);
      verify(mockStream2.write(any)).called(1);
    });

    test('handles concurrent stream creation for same peer', () async {
      final mockStream = MockP2PStream();
      final streamCreationCompleter = Completer<MockP2PStream>();
      
      when(mockStream.id()).thenReturn('stream-1');
      when(mockStream.isClosed).thenReturn(false);
      when(mockStream.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) => streamCreationCompleter.future);

      // Start two concurrent send operations
      final send1 = protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
      final send2 = protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);

      // Complete stream creation
      streamCreationCompleter.complete(mockStream);

      // Wait for both sends to complete
      await send1;
      await send2;

      // Verify stream was created only once despite concurrent calls
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(1);
      
      // Verify both messages were written
      verify(mockStream.write(any)).called(2);
    });

    test('closes stream on peer disconnect', () async {
      final mockStream = MockP2PStream();
      when(mockStream.id()).thenReturn('stream-1');
      when(mockStream.isClosed).thenReturn(false);
      when(mockStream.write(any)).thenAnswer((_) async {});
      when(mockStream.close()).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream);

      // Send a message to create the stream
      await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);

      // Close the peer stream
      await protocol.closePeerStream(mockPeer1);

      // Verify stream was closed
      verify(mockStream.close()).called(1);
    });

    test('removes and recreates stream after send error', () async {
      final mockStream1 = MockP2PStream();
      final mockStream2 = MockP2PStream();
      
      when(mockStream1.id()).thenReturn('stream-1');
      when(mockStream1.isClosed).thenReturn(false);
      when(mockStream1.write(any)).thenThrow(Exception('Write failed'));
      when(mockStream1.close()).thenAnswer((_) async {});
      
      when(mockStream2.id()).thenReturn('stream-2');
      when(mockStream2.isClosed).thenReturn(false);
      when(mockStream2.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream1);

      // First send should fail
      try {
        await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<Exception>());
      }

      // Verify failed stream was closed
      verify(mockStream1.close()).called(1);

      // Setup new stream
      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream2);

      // Second send should create new stream and succeed
      await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
      
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(2);
      verify(mockStream2.write(any)).called(1);
    });

    test('closes all streams on protocol close', () async {
      final mockStream1 = MockP2PStream();
      final mockStream2 = MockP2PStream();
      
      when(mockStream1.id()).thenReturn('stream-1');
      when(mockStream1.isClosed).thenReturn(false);
      when(mockStream1.write(any)).thenAnswer((_) async {});
      when(mockStream1.close()).thenAnswer((_) async {});
      
      when(mockStream2.id()).thenReturn('stream-2');
      when(mockStream2.isClosed).thenReturn(false);
      when(mockStream2.write(any)).thenAnswer((_) async {});
      when(mockStream2.close()).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream1);
      when(mockHost.newStream(mockPeer2, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream2);

      // Create streams to both peers
      await protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11);
      await protocol.sendRpc(mockPeer2, pb.RPC(), gossipSubIDv11);

      // Close protocol
      await protocol.close();

      // Verify both streams were closed
      verify(mockStream1.close()).called(1);
      verify(mockStream2.close()).called(1);
      
      // Verify protocol handler was unregistered
      verify(mockHost.removeStreamHandler(gossipSubIDv11)).called(1);
    });

    test('prevents new streams after protocol is closing', () async {
      // Start closing
      unawaited(protocol.close());

      // Try to send a message
      expect(
        () => protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11),
        throwsA(isA<StateError>()),
      );
    });

    test('handles rapid successive messages without stream leaks', () async {
      final mockStream = MockP2PStream();
      when(mockStream.id()).thenReturn('stream-1');
      when(mockStream.isClosed).thenReturn(false);
      when(mockStream.write(any)).thenAnswer((_) async {});

      when(mockHost.newStream(mockPeer1, [gossipSubIDv11], any))
          .thenAnswer((_) async => mockStream);

      // Send many messages rapidly
      final futures = <Future>[];
      for (int i = 0; i < 100; i++) {
        futures.add(protocol.sendRpc(mockPeer1, pb.RPC(), gossipSubIDv11));
      }

      await Future.wait(futures);

      // Verify stream was created only once
      verify(mockHost.newStream(mockPeer1, [gossipSubIDv11], any)).called(1);
      
      // Verify all messages were written
      verify(mockStream.write(any)).called(100);
      
      // Verify stream was never closed during rapid sends
      verifyNever(mockStream.close());
    });
  });
}


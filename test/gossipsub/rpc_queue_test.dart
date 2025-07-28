import 'dart:async';
import 'dart:collection';
import 'dart:typed_data'; // For Uint8List

import 'package:dcid/dcid.dart';
import 'package:dart_libp2p/core/routing/routing.dart';
import 'package:test/test.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart'; // Corrected PeerId import
import 'package:dart_libp2p/core/crypto/keys.dart'; // For PublicKey
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:dart_libp2p_pubsub/src/core/comm.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/rpc_queue.dart';

// Mock PeerId
class MockPeerId implements PeerId {
  final String _id;
  MockPeerId(this._id);

  @override
  String toFullBase58() => _id;

  @override
  String toBase58() => _id; // Simplified for testing

  @override
  List<int> get bytes => _id.codeUnits;

  @override
  bool equals(PeerId other) => other is MockPeerId && other._id == _id;

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => 'MockPeerId($_id)';

  @override
  int compareTo(PeerId other) {
    if (other is MockPeerId) {
      return _id.compareTo(other._id);
    }
    return _id.compareTo(other.toBase58());
  }

  @override
  bool isValid() => true;

  @override
  String pretty() => _id;

  // Adding stubs for missing PeerId interface members
  @override
  Future<PublicKey?> extractPublicKey() async {
    throw UnimplementedError('MockPeerId.extractPublicKey');
  }

  @override
  Map<String, dynamic> loggable() => {'id': _id, 'type': 'mock'}; // Changed to method

  @override
  bool matchesPrivateKey(dynamic privKey) {
    throw UnimplementedError('MockPeerId.matchesPrivateKey');
  }

  @override
  bool matchesPublicKey(dynamic pubKey) {
    throw UnimplementedError('MockPeerId.matchesPublicKey');
  }

  @override
  String toHexString() => UnimplementedError('MockPeerId.toHexString').toString(); // Or implement simply

  @override
  String toB58String() => _id; // Alias for toBase58

  @override
  bool operator ==(Object other) => other is MockPeerId && other._id == _id;

  @override
  String shortString() => _id.length > 6 ? _id.substring(0, 6) : _id;

  @override
  Uint8List toBytes() => Uint8List.fromList(bytes); // Corrected return type

  @override
  String toCIDString() {
    throw UnimplementedError('MockPeerId.toCIDString');
  }

  @override
  CID toCid() { // Corrected return type
    throw UnimplementedError('MockPeerId.toCid');
  }

  @override
  PublicKey? get publicKey => throw UnimplementedError('MockPeerId.publicKey');

  @override
  Map<String, dynamic> toJson() {
    return {'id': _id, 'type': 'mock'}; // Stub implementation
  }
}

// Mock PubSubProtocol
class MockPubSubProtocol implements PubSubProtocol {
  // final Completer<void> _sendRpcCompleter = Completer<void>(); // Replaced with per-call or onSendRpc logic
  PeerId? lastPeerId;
  pb.RPC? lastRpc;
  String? lastProtocolId;
  int sendRpcCallCount = 0;
  Function(PeerId, pb.RPC, String)? onSendRpc;
  bool _throwErrorOnSend = false;
  dynamic _errorToThrow;

  Future<void> sendRpc(PeerId peerId, pb.RPC rpc, String protocolId) async {
    sendRpcCallCount++;
    lastPeerId = peerId;
    lastRpc = rpc;
    lastProtocolId = protocolId;
    // REMOVED: onSendRpc?.call(peerId, rpc, protocolId); // This was redundant and causing issues

    if (_throwErrorOnSend) {
      if (_errorToThrow != null) {
        throw _errorToThrow;
      }
      throw Exception('MockPubSubProtocol: Simulated send error');
    }

    // Allow onSendRpc to provide a future to await, or control completion
    if (onSendRpc != null) {
      var result = onSendRpc!(peerId, rpc, protocolId);
      if (result is Future) { // Check if it's a Future
        return result as Future<void>;
      }
    }
    
    // Default: complete immediately if onSendRpc doesn't return a future
    return Future.value();
  }

  void prepareToSendError(dynamic error) {
    _throwErrorOnSend = true;
    _errorToThrow = error;
  }

  void resetSendError() {
    _throwErrorOnSend = false;
    _errorToThrow = null;
  }

  // Unimplemented methods from PubSubProtocol - add if needed for specific tests
  @override
  void handleConnection(PeerId peerId, Stream<List<int>> stream, StreamSink<List<int>> sink) {
    throw UnimplementedError();
  }

  @override
  void start() {
    throw UnimplementedError();
  }

  @override
  void stop() {
    throw UnimplementedError();
  }

  // Adding a stub for 'close' to satisfy analyzer, may need review based on PubSubProtocol definition
  Future<void> close() async {
    // No-op for mock, or implement if specific close behavior is needed for tests
  }
}

void main() {
  group('PeerRpcQueue', () {
    late MockPeerId mockPeerId;
    late MockPubSubProtocol mockComms;
    late PeerRpcQueue queue;
    const protocolId = 'test_protocol/1.0.0';

    setUp(() {
      mockPeerId = MockPeerId('peerA');
      mockComms = MockPubSubProtocol();
      queue = PeerRpcQueue(mockPeerId, mockComms, protocolId);
    });

    test('initial state is empty', () {
      expect(queue.length, 0);
    });

    test('add() increases queue length and attempts to send', () async {
      final rpc = pb.RPC();
      queue.add(rpc);
      expect(queue.length, 1);
      // Allow microtask to run for _trySend
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastRpc, rpc);
      expect(mockComms.lastPeerId, mockPeerId);
      expect(mockComms.lastProtocolId, protocolId);
      // After successful send, queue should be empty
      expect(queue.length, 0);
    });

    test('add() multiple RPCs are sent in order', () async {
      // Create distinct RPCs by populating a field, e.g., publish list
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));
      final rpc3 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([3]));

      final sentRPCs = <pb.RPC>[];
      mockComms.onSendRpc = (peerId, rpc, protocolId) {
        sentRPCs.add(rpc);
      };

      queue.add(rpc1);
      queue.add(rpc2);
      queue.add(rpc3);

      expect(queue.length, 3); // All added before first send completes

      // Allow microtasks for all send operations
      await Future.delayed(Duration.zero); // For first _trySend
      await Future.delayed(Duration.zero); // For second _trySend (if needed, depends on async nature)
      await Future.delayed(Duration.zero); // For third _trySend

      expect(mockComms.sendRpcCallCount, 3);
      expect(queue.length, 0);
      expect(sentRPCs.length, 3);
      expect(sentRPCs[0], rpc1);
      expect(sentRPCs[1], rpc2);
      expect(sentRPCs[2], rpc3);
    });

    test('_trySend stops on error and keeps message in queue', () async {
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2])); // This one should not be sent

      mockComms.prepareToSendError(Exception('Send failed!'));

      queue.add(rpc1);
      queue.add(rpc2);

      expect(queue.length, 2);

      await Future.delayed(Duration.zero); // Allow _trySend to run

      expect(mockComms.sendRpcCallCount, 1); // Only first attempt
      expect(queue.length, 2); // Message remains due to error, second one not attempted
      expect(mockComms.lastRpc, rpc1); // Attempted to send rpc1

      // Verify _isSending is false after error
      // This is tricky to test directly without exposing _isSending or more complex mock.
      // We can infer it by trying to add another message and seeing if it attempts to send.
      mockComms.resetSendError(); // Allow next send to succeed
      mockComms.sendRpcCallCount = 0; // Reset counter

      final rpc3 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([3]));
      queue.add(rpc3); // Queue is now [rpc1, rpc2, rpc3]
      expect(queue.length, 3);

      // _trySend should be called because _isSending was reset by the error path.
      // It will try to send rpc1, then rpc2, then rpc3.
      await Future.delayed(Duration.zero); // Allow the new _trySend to process the whole queue
      expect(mockComms.sendRpcCallCount, 3, reason: "rpc1, rpc2, and rpc3 should be sent");
      expect(queue.length, 0, reason: "Queue should be empty after all messages are sent");
    });

    test('clear() removes all messages from the queue', () async {
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));
      queue.add(rpc1);
      queue.add(rpc2);
      
      // Ensure rpc1 and rpc2 are processed and _isSending becomes false
      await Future.delayed(Duration.zero); // Allow rpc1 send to start
      await Future.delayed(Duration.zero); // Allow rpc2 send to start and for loop to finish
      // At this point, if sends are immediate in mock, queue should be empty and _isSending false.
      expect(queue.length, 0, reason: "Queue should be empty after rpc1, rpc2 processed before clear");
      expect(mockComms.sendRpcCallCount, 2, reason: "rpc1 and rpc2 should have been sent before clear");

      queue.clear();
      expect(queue.length, 0);

      mockComms.sendRpcCallCount = 0; // Reset for the next part of the test.
      final rpc3 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([3]));
      queue.add(rpc3);
      await Future.delayed(Duration.zero); // Allow rpc3 to be sent.
      
      expect(mockComms.sendRpcCallCount, 1, reason: "rpc3 should be sent after clear");
      expect(mockComms.lastRpc, rpc3);
      expect(queue.length, 0, reason: "Queue should be empty after rpc3 sent");
    });

     test('_trySend does not run concurrently', () async {
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));

      final sendCompleter1 = Completer<void>();
      int actualSends = 0;

      mockComms.onSendRpc = (p, r, protoId) { // Explicitly async for clarity if returning Future
        actualSends++;
        if (r == rpc1) {
          return sendCompleter1.future; // This future will be awaited by PeerRpcQueue
        }
        return Future.value(); // Other sends complete immediately
      };

      queue.add(rpc1); // This will call _trySend, which will await sendCompleter1.future
      await Future.delayed(Duration.zero); // Let the first _trySend start and hang

      expect(actualSends, 1); // First send initiated
      expect(queue.length, 1); // rpc1 is in queue, being "sent"

      // Now add another RPC. If _isSending works, _trySend should not start a new send loop.
      queue.add(rpc2);
      expect(queue.length, 2); // rpc2 added to queue
      await Future.delayed(Duration.zero); // Give time for a potential second _trySend

      expect(actualSends, 1); // Still only 1 send initiated, because the first one is "in progress"

      // Now complete the first send
      sendCompleter1.complete();
      await Future.delayed(Duration.zero); // Allow the first send to complete and the loop to continue

      expect(actualSends, 2); // Second send (rpc2) should now have occurred
      expect(queue.length, 0); // Both messages processed
    });
  });

  group('RpcOutgoingQueueManager', () {
    late MockPubSubProtocol mockComms;
    late RpcOutgoingQueueManager manager;
    const defaultProtocolId = 'default_protocol/1.0.0';

    setUp(() {
      mockComms = MockPubSubProtocol();
      manager = RpcOutgoingQueueManager(mockComms, defaultProtocolId);
    });

    test('sendRpc creates new PeerRpcQueue if one does not exist', () async {
      final peerA = MockPeerId('peerA');
      final rpc = pb.RPC();

      manager.sendRpc(peerA, rpc);
      await Future.delayed(Duration.zero); // Allow PeerRpcQueue's _trySend to execute

      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastPeerId, peerA);
      expect(mockComms.lastRpc, rpc);
      expect(mockComms.lastProtocolId, defaultProtocolId);
    });

    test('sendRpc uses existing PeerRpcQueue for the same peer', () async {
      final peerA = MockPeerId('peerA');
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));

      manager.sendRpc(peerA, rpc1);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastRpc, rpc1);

      manager.sendRpc(peerA, rpc2);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2); // Total sends
      expect(mockComms.lastRpc, rpc2); // Last sent RPC
    });

    test('sendRpc uses specified protocolId', () async {
      final peerA = MockPeerId('peerA');
      final rpc = pb.RPC();
      const customProtocolId = 'custom_protocol/1.0.0';

      manager.sendRpc(peerA, rpc, protocolId: customProtocolId);
      await Future.delayed(Duration.zero);

      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastProtocolId, customProtocolId);
    });

    test('sendRpc uses default protocolId if not specified', () async {
      final peerA = MockPeerId('peerA');
      final rpc = pb.RPC();

      manager.sendRpc(peerA, rpc); // No protocolId specified
      await Future.delayed(Duration.zero);

      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastProtocolId, defaultProtocolId);
    });

    test('sendRpc with different protocolId for existing queue (logs warning, uses original)', () async {
      final peerA = MockPeerId('peerA');
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));
      const customProtocolId = 'custom_protocol/1.0.0';

      // First send, establishes queue with defaultProtocolId
      manager.sendRpc(peerA, rpc1);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastProtocolId, defaultProtocolId);

      // Second send to same peer, but with a custom protocolId
      // Current implementation should log a warning and use the original protocolId
      // (Need to capture print output or modify RpcOutgoingQueueManager to test warning better)
      manager.sendRpc(peerA, rpc2, protocolId: customProtocolId);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2);
      expect(mockComms.lastRpc, rpc2);
      expect(mockComms.lastProtocolId, defaultProtocolId); // Still uses the original
    });

    test('peerDisconnected removes and clears the queue for a peer', () async {
      final peerA = MockPeerId('peerA');
      final peerB = MockPeerId('peerB');
      final rpcA = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpcB = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));

      manager.sendRpc(peerA, rpcA);
      manager.sendRpc(peerB, rpcB);
      await Future.delayed(Duration.zero); // Let initial sends attempt
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2);

      // Disconnect peerA
      manager.peerDisconnected(peerA);

      // Try sending to peerA again, should create a new queue and send
      mockComms.sendRpcCallCount = 0; // Reset for clarity
      manager.sendRpc(peerA, rpcA);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1); // Sent via a new queue for peerA
      expect(mockComms.lastPeerId, peerA);

      // Sending to peerB should still work via its existing queue
      final rpcB2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([3]));
      manager.sendRpc(peerB, rpcB2);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2); // Total sends for this block
      expect(mockComms.lastPeerId, peerB);
      expect(mockComms.lastRpc, rpcB2);
    });

    test('clearAll clears all peer queues', () async {
      final peerA = MockPeerId('peerA');
      final peerB = MockPeerId('peerB');
      final rpcA = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpcB = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));

      manager.sendRpc(peerA, rpcA);
      manager.sendRpc(peerB, rpcB);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2);

      manager.clearAll();
      mockComms.sendRpcCallCount = 0; // Reset for clarity

      // Try sending to peerA again, should create a new queue
      manager.sendRpc(peerA, rpcA);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastPeerId, peerA);

      // Try sending to peerB again, should create a new queue
      manager.sendRpc(peerB, rpcB);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 2);
      expect(mockComms.lastPeerId, peerB);
    });
  });
}

extension RpcShortString on pb.RPC {
  String toShortString() {
    if (this.subscriptions.isNotEmpty) return "RPC(Subscriptions)";
    if (this.publish.isNotEmpty) return "RPC(Publish)";
    if (this.hasControl()) return "RPC(Control)";
    return "RPC(Empty)";
  }
}

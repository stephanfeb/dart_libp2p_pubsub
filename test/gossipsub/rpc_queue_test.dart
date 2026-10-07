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
  @override
  void Function(PeerId peerId, String protocol)? onNewInboundPeer;

  @override
  void Function(PeerId peerId)? onPeerDead;

  @override
  int maxMessageSize = 1 << 20;

  @override
  Duration streamCloseTimeout = defaultStreamCloseTimeout;

  @override
  List<String> get protocols => const ['/meshsub/1.1.0'];

  @override
  String? protocolOf(PeerId peerId) => null;

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
  void start() {}

  @override
  void stop() {
    throw UnimplementedError();
  }

  // Adding a stub for 'close' to satisfy analyzer, may need review based on PubSubProtocol definition
  Future<void> close() async {
    // No-op for mock, or implement if specific close behavior is needed for tests
  }

  @override
  Future<void> closePeerStream(PeerId peerId) {
    // TODO: implement closePeerStream
    throw UnimplementedError();
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

    test('add() sends the RPC at once', () async {
      final rpc = pb.RPC();
      expect(queue.add(rpc), isTrue);
      await Future.delayed(Duration.zero);
      expect(mockComms.sendRpcCallCount, 1);
      expect(mockComms.lastRpc, rpc);
      expect(mockComms.lastPeerId, mockPeerId);
      expect(mockComms.lastProtocolId, protocolId);
      expect(queue.length, 0);
    });

    test('add() multiple RPCs are sent in order', () async {
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
      // rpc1 is being sent; rpc2 and rpc3 wait.
      expect(queue.length, 2);

      await Future.delayed(Duration.zero);
      expect(sentRPCs, [rpc1, rpc2, rpc3]);
      expect(queue.length, 0);
    });

    test('an RPC that fails to send is dropped and the next ones are sent', () async {
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));
      var calls = 0;
      mockComms.onSendRpc = (peerId, rpc, protocolId) {
        calls++;
        if (rpc == rpc1) throw Exception('Send failed!');
      };

      queue.add(rpc1);
      queue.add(rpc2);
      await Future.delayed(Duration.zero);

      expect(calls, 2);
      expect(mockComms.lastRpc, rpc2);
      expect(queue.length, 0, reason: 'nothing stays stuck in the queue');
    });

    test('a full queue refuses RPCs, and urgent RPCs go first', () async {
      final bounded = PeerRpcQueue(mockPeerId, mockComms, protocolId, maxSize: 3);
      final hold = Completer<void>();
      final sent = <int>[];
      mockComms.onSendRpc = (peerId, rpc, protocolId) {
        sent.add(rpc.publish.single.data.single);
        return sent.length == 1 ? hold.future : Future.value();
      };
      pb.RPC rpc(int n) => pb.RPC()..publish.add(pb.Message()..data = [n]);

      expect(bounded.add(rpc(1)), isTrue); // Being sent.
      expect(bounded.add(rpc(2)), isTrue);
      expect(bounded.add(rpc(3)), isTrue);
      expect(bounded.add(rpc(4), urgent: true), isTrue);
      expect(bounded.length, 3);
      expect(bounded.add(rpc(5)), isFalse); // Full.
      expect(bounded.add(rpc(6), urgent: true), isFalse);

      hold.complete();
      await Future.delayed(Duration.zero);
      expect(sent, [1, 4, 2, 3]);
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

    test('sends one RPC at a time', () async {
      final rpc1 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      final rpc2 = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([2]));
      final sendCompleter1 = Completer<void>();
      var actualSends = 0;
      mockComms.onSendRpc = (p, r, protoId) {
        actualSends++;
        return r == rpc1 ? sendCompleter1.future : Future.value();
      };

      queue.add(rpc1);
      await Future.delayed(Duration.zero);
      expect(actualSends, 1);

      queue.add(rpc2);
      expect(queue.length, 1);
      await Future.delayed(Duration.zero);
      expect(actualSends, 1, reason: 'rpc2 waits for rpc1');

      sendCompleter1.complete();
      await Future.delayed(Duration.zero);
      expect(actualSends, 2);
      expect(queue.length, 0);
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

import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/connmgr/conn_manager.dart';
import 'package:dart_libp2p/core/event/bus.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/interfaces.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/peerstore.dart';
import 'package:dart_libp2p/p2p/protocol/holepunch/holepunch_service.dart';
import 'package:dart_libp2p_pubsub/src/core/comm.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/rpc_queue.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

final Logger _logger = Logger("NetworkFailureCrashTest");

void main() {
  // Configure logging to see all details
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      print('ERROR: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('STACKTRACE: ${record.stackTrace}');
    }
  });

  group('Network Failure Crash Tests', () {
    test('Test 1: Dial failure with "No transport found" error should not crash', () async {
      _logger.info('Starting Test 1: No transport found error');
      
      final hostA = await createHost();
      
      // Create a PubSubProtocol for hostA
      int rpcReceivedCount = 0;
      final comms = PubSubProtocol(
        hostA,
        (peerId, rpc) async {
          rpcReceivedCount++;
        },
      );
      
      // Create PeerRpcQueue for a peer that doesn't exist in the network
      // This will cause a "Failed to dial" or similar error
      final fakePeerId = await PeerId.random();
      final queue = PeerRpcQueue(fakePeerId, comms, gossipSubIDv11);
      
      // Try to send an RPC - this should fail because fakePeerId is not in the network
      final rpc = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1, 2, 3]));
      
      _logger.info('Adding RPC to queue for non-existent peer $fakePeerId');
      
      // This is the critical part - the error should be caught internally
      // but historically it was also escaping as unhandled, causing crashes
      var unhandledError;
      
      // Catch any unhandled errors in this zone
      await runZonedGuarded(() async {
        queue.add(rpc);
        
        // Wait for the send attempt to fail
        await Future.delayed(Duration(milliseconds: 500));
      }, (error, stackTrace) {
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE: $error', error, stackTrace);
      });
      
      _logger.info('Test 1 completed');
      
      // Cleanup
      await comms.close();
      await hostA.close();
      
      // The test passes if no unhandled error escaped
      expect(unhandledError, isNull, 
          reason: 'No unhandled error should escape from PeerRpcQueue.add()');
      expect(rpcReceivedCount, equals(0), 
          reason: 'No RPC should have been received since peer does not exist');
      expect(queue.length, greaterThan(0), 
          reason: 'RPC should remain in queue after send failure');
    });

    test('Test 2: Stream creation timeout error should not crash', () async {
      _logger.info('Starting Test 2: Stream creation timeout');
      
      // Create a MockHost that simulates a timeout on newStream
      final hostA = await createHost();
      final timeoutHost = TimeoutSimulatingHost(hostA);
      
      int rpcReceivedCount = 0;
      final comms = PubSubProtocol(
        timeoutHost,
        (peerId, rpc) async {
          rpcReceivedCount++;
        },
      );
      
      // Create a peer that will timeout
      final slowPeerId = await PeerId.random();
      final queue = PeerRpcQueue(slowPeerId, comms, gossipSubIDv11);
      
      final rpc = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1, 2, 3]));
      
      _logger.info('Adding RPC to queue with timeout-simulating host');
      
      var unhandledError;
      
      // Catch any unhandled errors in this zone
      await runZonedGuarded(() async {
        queue.add(rpc);
        
        // Wait for timeout to occur (but not the full 15 seconds)
        // The timeout will be caught internally
        await Future.delayed(Duration(milliseconds: 500));
      }, (error, stackTrace) {
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE: $error', error, stackTrace);
      });
      
      _logger.info('Test 2 completed');
      
      // Cleanup
      await comms.close();
      await hostA.close();
      
      // The test passes if no unhandled error escaped
      expect(unhandledError, isNull, 
          reason: 'No unhandled error should escape from PeerRpcQueue.add() even on timeout');
      expect(rpcReceivedCount, equals(0));
    });

    test('Test 3: Multiple concurrent send failures should not crash', () async {
      _logger.info('Starting Test 3: Multiple concurrent send failures');
      
      final hostA = await createHost();
      
      int rpcReceivedCount = 0;
      final comms = PubSubProtocol(
        hostA,
        (peerId, rpc) async {
          rpcReceivedCount++;
        },
      );
      
      // Create multiple fake peers
      final fakePeers = await Future.wait([
        PeerId.random(),
        PeerId.random(),
        PeerId.random(),
      ]);
      
      // Create queues for each fake peer
      final queues = fakePeers.map((peerId) => 
        PeerRpcQueue(peerId, comms, gossipSubIDv11)
      ).toList();
      
      final rpc = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1, 2, 3]));
      
      _logger.info('Adding RPCs to multiple queues simultaneously');
      
      var unhandledError;
      var errorCount = 0;
      
      // Catch any unhandled errors in this zone
      await runZonedGuarded(() async {
        // Send to all peers at once - all should fail
        for (final queue in queues) {
          queue.add(rpc);
        }
        
        // Wait for all send attempts to fail
        await Future.delayed(Duration(milliseconds: 800));
      }, (error, stackTrace) {
        errorCount++;
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE (error #$errorCount): $error', error, stackTrace);
      });
      
      _logger.info('Test 3 completed - caught $errorCount unhandled errors');
      
      // Cleanup
      await comms.close();
      await hostA.close();
      
      // The test passes if no unhandled error escaped
      expect(unhandledError, isNull, 
          reason: 'No unhandled errors should escape from concurrent PeerRpcQueue.add() calls');
      expect(rpcReceivedCount, equals(0));
    });

    test('Test 4: Error during control message send should not crash', () async {
      _logger.info('Starting Test 4: Control message send failure');
      
      final hostA = await createHost();
      
      int rpcReceivedCount = 0;
      final comms = PubSubProtocol(
        hostA,
        (peerId, rpc) async {
          rpcReceivedCount++;
        },
      );
      
      final fakePeerId = await PeerId.random();
      final queue = PeerRpcQueue(fakePeerId, comms, gossipSubIDv11);
      
      // Create a control message (like heartbeat)
      final controlRpc = pb.RPC()..control = pb.ControlMessage();
      
      _logger.info('Adding control RPC to queue for non-existent peer');
      
      var unhandledError;
      
      await runZonedGuarded(() async {
        queue.add(controlRpc);
        
        // Wait for the send attempt to fail
        await Future.delayed(Duration(milliseconds: 500));
      }, (error, stackTrace) {
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE: $error', error, stackTrace);
      });
      
      _logger.info('Test 4 completed');
      
      // Cleanup
      await comms.close();
      await hostA.close();
      
      expect(unhandledError, isNull, 
          reason: 'Control message send failure should not cause unhandled error');
      expect(rpcReceivedCount, equals(0));
    });

    test('Test 5: Exception that matches real stack trace - No transport found', () async {
      _logger.info('Starting Test 5: Exact match for "No transport found" error');
      
      final hostA = await createHost();
      final failingHost = NoTransportHost(hostA);
      
      final comms = PubSubProtocol(
        failingHost,
        (peerId, rpc) async {
          // Receive callback
        },
      );
      
      final fakePeerId = await PeerId.random();
      final queue = PeerRpcQueue(fakePeerId, comms, gossipSubIDv11);
      
      final rpc = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      
      _logger.info('Adding RPC that will trigger "No transport found" error');
      
      var unhandledError;
      
      await runZonedGuarded(() async {
        queue.add(rpc);
        await Future.delayed(Duration(milliseconds: 500));
      }, (error, stackTrace) {
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE: $error', error, stackTrace);
      });
      
      _logger.info('Test 5 completed');
      
      await comms.close();
      await hostA.close();
      
      expect(unhandledError, isNull, 
          reason: '"No transport found" error should not escape as unhandled');
    });

    test('Test 6: UDX timeout exception should not crash', () async {
      _logger.info('Starting Test 6: UDX timeout exception');
      
      final hostA = await createHost();
      final udxTimeoutHost = UDXTimeoutHost(hostA);
      
      final comms = PubSubProtocol(
        udxTimeoutHost,
        (peerId, rpc) async {
          // Receive callback
        },
      );
      
      final fakePeerId = await PeerId.random();
      final queue = PeerRpcQueue(fakePeerId, comms, gossipSubIDv11);
      
      final rpc = pb.RPC()..publish.add(pb.Message()..data = Uint8List.fromList([1]));
      
      _logger.info('Adding RPC that will trigger UDX timeout error');
      
      var unhandledError;
      
      await runZonedGuarded(() async {
        queue.add(rpc);
        await Future.delayed(Duration(milliseconds: 500));
      }, (error, stackTrace) {
        unhandledError = error;
        _logger.severe('UNHANDLED ERROR CAUGHT IN ZONE: $error', error, stackTrace);
      });
      
      _logger.info('Test 6 completed');
      
      await comms.close();
      await hostA.close();
      
      expect(unhandledError, isNull, 
          reason: 'UDX timeout error should not escape as unhandled');
    });
  });
}

/// A Host wrapper that simulates timeouts on newStream calls
class TimeoutSimulatingHost implements Host {
  final Host _wrapped;

  TimeoutSimulatingHost(this._wrapped);

  @override
  Future<P2PStream> newStream(PeerId remotePeerId, List<String> protocols, [dynamic context]) async {
    // Simulate a timeout - but don't actually wait 15 seconds in the test
    // Just throw the timeout immediately
    throw TimeoutException('Simulated timeout in newStream', Duration(seconds: 10));
  }

  // Delegate all other methods to the wrapped host
  @override
  PeerId get id => _wrapped.id;

  @override
  List<MultiAddr> get addrs => _wrapped.addrs;

  @override
  Network get network => _wrapped.network;

  @override
  Peerstore get peerStore => _wrapped.peerStore;

  @override
  ConnManager get connManager => _wrapped.connManager;

  @override
  EventBus get eventBus => _wrapped.eventBus;

  @override
  ProtocolSwitch get mux => _wrapped.mux;

  @override
  Future<void> close() => _wrapped.close();

  @override
  Future<void> connect(AddrInfo peer, {Context? context}) => _wrapped.connect(peer, context: context);

  @override
  void removeStreamHandler(String protocol) => _wrapped.removeStreamHandler(protocol);

  @override
  void setStreamHandler(String protocol, StreamHandler handler) => _wrapped.setStreamHandler(protocol, handler);

  @override
  void setStreamHandlerMatch(String protocol, dynamic match, StreamHandler handler) => 
      _wrapped.setStreamHandlerMatch(protocol, match, handler);

  @override
  Future<void> start() => _wrapped.start();

  @override
  HolePunchService? get holePunchService => null;
}

/// A Host wrapper that simulates "No transport found" errors
class NoTransportHost implements Host {
  final Host _wrapped;

  NoTransportHost(this._wrapped);

  @override
  Future<P2PStream> newStream(PeerId remotePeerId, List<String> protocols, [dynamic context]) async {
    // Simulate the exact error from the stack trace
    final fakeAddr = '/ip4/128.199.163.136/udp/55222/udx/p2p/12D3KooWQcZy5KFPMLQCbB9CQ2CqGvb88etQ8wxoESbXQgF1PNkU/p2p-circuit/p2p/${remotePeerId.toBase58()}';
    throw Exception('Failed to dial: Exception: All dial attempts failed: Exception: Failed to dial any address. Errors: $fakeAddr: Exception: No transport found for address: $fakeAddr');
  }

  @override
  PeerId get id => _wrapped.id;

  @override
  List<MultiAddr> get addrs => _wrapped.addrs;

  @override
  Network get network => _wrapped.network;

  @override
  Peerstore get peerStore => _wrapped.peerStore;

  @override
  ConnManager get connManager => _wrapped.connManager;

  @override
  EventBus get eventBus => _wrapped.eventBus;

  @override
  ProtocolSwitch get mux => _wrapped.mux;

  @override
  Future<void> close() => _wrapped.close();

  @override
  Future<void> connect(AddrInfo peer, {Context? context}) => _wrapped.connect(peer, context: context);

  @override
  void removeStreamHandler(String protocol) => _wrapped.removeStreamHandler(protocol);

  @override
  void setStreamHandler(String protocol, StreamHandler handler) => _wrapped.setStreamHandler(protocol, handler);

  @override
  void setStreamHandlerMatch(String protocol, dynamic match, StreamHandler handler) => 
      _wrapped.setStreamHandlerMatch(protocol, match, handler);

  @override
  Future<void> start() => _wrapped.start();

  @override
  HolePunchService? get holePunchService => null;
}

/// A Host wrapper that simulates UDX timeout errors
class UDXTimeoutHost implements Host {
  final Host _wrapped;

  UDXTimeoutHost(this._wrapped);

  @override
  Future<P2PStream> newStream(PeerId remotePeerId, List<String> protocols, [dynamic context]) async {
    // Simulate UDX timeout error from the stack trace
    final error = 'Failed to dial: Exception: All dial attempts failed: Exception: Failed to dial any address. Errors: '
        '/ip4/164.92.167.82/udp/4002/udx: UDXTransportException: UDX operation timed out after 30000ms (context: UDPSocket.handshakeComplete(164.92.167.82:4002), transient: true); '
        '/ip4/164.92.167.82/udp/34050/udx: UDXTransportException: UDX operation timed out after 30000ms (context: UDPSocket.handshakeComplete(164.92.167.82:34050), transient: true); '
        '/ip4/164.92.167.82/udp/42956/udx: UDXTransportException: UDX operation timed out after 30000ms (context: UDPSocket.handshakeComplete(164.92.167.82:42956), transient: true)';
    throw Exception(error);
  }

  @override
  PeerId get id => _wrapped.id;

  @override
  List<MultiAddr> get addrs => _wrapped.addrs;

  @override
  Network get network => _wrapped.network;

  @override
  Peerstore get peerStore => _wrapped.peerStore;

  @override
  ConnManager get connManager => _wrapped.connManager;

  @override
  EventBus get eventBus => _wrapped.eventBus;

  @override
  ProtocolSwitch get mux => _wrapped.mux;

  @override
  Future<void> close() => _wrapped.close();

  @override
  Future<void> connect(AddrInfo peer, {Context? context}) => _wrapped.connect(peer, context: context);

  @override
  void removeStreamHandler(String protocol) => _wrapped.removeStreamHandler(protocol);

  @override
  void setStreamHandler(String protocol, StreamHandler handler) => _wrapped.setStreamHandler(protocol, handler);

  @override
  void setStreamHandlerMatch(String protocol, dynamic match, StreamHandler handler) => 
      _wrapped.setStreamHandlerMatch(protocol, match, handler);

  @override
  Future<void> start() => _wrapped.start();

  @override
  HolePunchService? get holePunchService => null;
}


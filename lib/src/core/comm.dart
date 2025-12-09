import 'dart:async';
import 'dart:typed_data';

// Corrected imports based on PeerId's location and typical libp2p structure
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/stream.dart'; // Using P2PStream directly
import 'package:dart_libp2p/core/network/context.dart' as p2p_context; // For Host.newStream context
import 'package:dart_libp2p/p2p/transport/multiplexing/yamux/yamux_exceptions.dart';
import 'package:dart_libp2p/p2p/protocol/identify/identify_exceptions.dart';

import '../pb/rpc.pb.dart' as pb;

// Protocol IDs
// Note: go-libp2p-pubsub uses "/meshsub/1.1.0" for GossipSub v1.1
// and "/floodsub/1.0.0" for FloodSub.
// Other versions like GossipSub v1.0 ("/meshsub/1.0.0") also exist.
// We'll primarily focus on GossipSub v1.1.0.

const String gossipSubIDv11 = '/meshsub/1.1.0';
const String floodSubID = '/floodsub/1.0.0';
// Potentially add more as needed, e.g., gossipSubIDv10 = '/meshsub/1.0.0';

/// Represents a persistent outbound stream to a peer.
class _PersistentStream {
  final P2PStream stream;
  final PeerId peerId;
  final DateTime createdAt;
  bool _isClosed = false;

  _PersistentStream({
    required this.stream,
    required this.peerId,
  }) : createdAt = DateTime.now();

  bool get isClosed => _isClosed || stream.isClosed;

  Future<void> close() async {
    if (!_isClosed) {
      _isClosed = true;
      await stream.close();
    }
  }
}

/// Handles the raw communication for PubSub messages over libp2p.
///
/// This class is responsible for:
/// - Registering protocol handlers with the libp2p Host.
/// - Encoding and decoding RPC messages.
/// - Sending RPC messages to peers using persistent streams.
/// - Receiving RPC messages from peers and forwarding them for processing.
class PubSubProtocol {
  final Host _host;
  final Future<void> Function(PeerId peerId, pb.RPC rpc) _onRpcReceived;

  /// Map of persistent outbound streams per peer
  final Map<PeerId, _PersistentStream> _outboundStreams = {};

  /// Lock for managing stream creation per peer
  final Map<PeerId, Completer<_PersistentStream>> _streamCreationLocks = {};

  bool _isClosing = false;

  /// Creates a new [PubSubProtocol] instance.
  ///
  /// [_host] is the libp2p Host.
  /// [_onRpcReceived] is a callback function that will be invoked when a new
  /// RPC message is received from a peer.
  PubSubProtocol(this._host, this._onRpcReceived) {
    _host.setStreamHandler(gossipSubIDv11, _handleNewStreamData);
    // TODO: Register for other supported protocols like floodSubID if needed.
    print('PubSubProtocol initialized with persistent streams for $gossipSubIDv11.');
  }

  /// Internal handler for new streams, adapting to the Host's setStreamHandler signature.
  Future<void> _handleNewStreamData(P2PStream stream, PeerId remotePeer) async {
    print('Received incoming PubSub stream ${stream.id()} from $remotePeer on protocol ${stream.protocol()}');
    try {
      // Read all data from the stream.
      // P2PStream.read() should give us the data, assuming it handles length-prefixing
      // or that PubSub messages are sent as a single chunk per RPC.
      // This might need refinement if messages are large or chunked.
      final Uint8List bytes = await stream.read();

      if (bytes.isEmpty) {
        print('Incoming PubSub stream from $remotePeer closed with no data.');
        // Stream should be closed by the remote or by us in finally if not already.
        return;
      }

      // Decode the RPC message
      final rpc = pb.RPC.fromBuffer(bytes);
      print('Decoded RPC from $remotePeer: ${rpc.toShortString()}');

      // Pass to the callback for processing
      await _onRpcReceived(remotePeer, rpc);
    } catch (e, s) {
      print('Error handling incoming PubSub stream from $remotePeer: $e');
      print(s);
      await stream.reset(); // Reset stream on error
    } finally {
      if (!stream.isClosed) {
        await stream.close(); // Ensure stream is closed
      }
    }
  }

  /// Gets or creates a persistent stream for the given peer.
  ///
  /// Returns a [_PersistentStream] that can be reused for multiple messages.
  /// Uses a lock to prevent concurrent stream creation for the same peer.
  Future<_PersistentStream> _getOrCreateStream(PeerId peerId, String protocolId) async {
    if (_isClosing) {
      throw StateError('PubSubProtocol is closing, cannot create new streams');
    }

    // Check if we already have a valid stream
    final existingStream = _outboundStreams[peerId];
    if (existingStream != null && !existingStream.isClosed) {
      return existingStream;
    }

    // Remove closed stream if present
    if (existingStream != null) {
      _outboundStreams.remove(peerId);
      print('Removed closed stream for peer $peerId');
    }

    // Check if another call is already creating a stream for this peer
    final lock = _streamCreationLocks[peerId];
    if (lock != null && !lock.isCompleted) {
      print('Waiting for concurrent stream creation for peer $peerId');
      return await lock.future;
    }

    // Create new lock for this stream creation
    final newLock = Completer<_PersistentStream>();
    _streamCreationLocks[peerId] = newLock;

    try {
      print('Creating new persistent stream to $peerId on protocol $protocolId');
      final stream = await _host.newStream(peerId, [protocolId], p2p_context.Context());

      final persistentStream = _PersistentStream(
        stream: stream,
        peerId: peerId,
      );

      _outboundStreams[peerId] = persistentStream;
      newLock.complete(persistentStream);
      print('Created persistent stream to $peerId (stream id: ${stream.id()})');

      return persistentStream;
    } on IdentifyTimeoutException catch (e, s) {
      // Handle identify timeout gracefully - this is a recoverable error.
      // The peer may have gone offline or be temporarily unreachable.
      newLock.completeError(e, s);
      print('PubSubProtocol: Identify timeout creating stream to $peerId. Peer may be unreachable: $e');
      rethrow;
    } on IdentifyException catch (e, s) {
      // Handle other identify exceptions
      newLock.completeError(e, s);
      print('PubSubProtocol: Identify error creating stream to $peerId: $e');
      rethrow;
    } catch (e, s) {
      newLock.completeError(e, s);
      print('Failed to create stream to $peerId: $e');
      rethrow;
    } finally {
      _streamCreationLocks.remove(peerId);
    }
  }

  /// Sends an RPC message to a specific peer using a persistent stream.
  ///
  /// [peerId] is the recipient peer.
  /// [rpc] is the RPC message to send.
  /// [protocolId] is the specific PubSub protocol ID to use.
  Future<void> sendRpc(PeerId peerId, pb.RPC rpc, String protocolId) async {
    print('Attempting to send RPC to $peerId on protocol $protocolId: ${rpc.toShortString()}');
    
    if (_isClosing) {
      throw StateError('PubSubProtocol is closing, cannot send RPC');
    }

    // Try up to 2 times (initial + 1 retry) for stream state issues
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // Get or create persistent stream
        final persistentStream = await _getOrCreateStream(peerId, protocolId);

        // Check stream is writable (race condition protection)
        if (!persistentStream.stream.isWritable) {
          print('Stream to $peerId not writable, removing from cache');
          _outboundStreams.remove(peerId);
          if (attempt == 0) {
            continue; // Retry with fresh stream
          }
          throw StateError('Stream to $peerId not writable after retry');
        }

        // Encode the RPC message
        final bytes = rpc.writeToBuffer();

        // Write to the persistent stream (do NOT close it)
        await persistentStream.stream.write(bytes);

        print('RPC sent to $peerId on persistent stream successfully.');
        return; // Success
        
      } on YamuxStreamStateException catch (e) {
        // Stream state error - retry once with fresh stream
        if (attempt == 0) {
          print('Stream to $peerId in state ${e.currentState}, removing and retrying...');
          final stream = _outboundStreams.remove(peerId);
          if (stream != null) {
            await stream.close().catchError((_) {});
          }
          continue; // Retry
        }
        
        // Second attempt failed, clean up and rethrow
        print('Failed to send RPC to $peerId after retry: ${e.message}');
        _outboundStreams.remove(peerId);
        rethrow;
        
      } on IdentifyTimeoutException catch (e, s) {
        // Identify timeout - peer may have gone offline. Handle gracefully.
        print('PubSubProtocol: Identify timeout sending RPC to $peerId. Peer unreachable: $e');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close().catchError((err) {
            print('Error closing stream to $peerId after identify timeout: $err');
          });
        }
        // Don't rethrow - this is a recoverable error that the RPC queue will handle
        rethrow;
      } on IdentifyException catch (e, s) {
        // Other identify error - handle gracefully
        print('PubSubProtocol: Identify error sending RPC to $peerId: $e\n$s');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close().catchError((err) {
            print('Error closing stream to $peerId after identify error: $err');
          });
        }
        rethrow;
      } catch (e, s) {
        // Any other exception type - don't retry, just fail
        print('Error sending RPC to $peerId on $protocolId: $e\n$s');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close().catchError((err) {
            print('Error closing failed stream to $peerId: $err');
          });
        }
        rethrow;
      }
    }
  }

  /// Closes the persistent stream to a peer (e.g., when peer disconnects).
  Future<void> closePeerStream(PeerId peerId) async {
    final stream = _outboundStreams.remove(peerId);
    if (stream != null) {
      print('Closing persistent stream to $peerId');
      await stream.close();
    }
  }

  /// Closes the protocol handler and cleans up resources.
  Future<void> close() async {
    _isClosing = true;

    // Close all persistent outbound streams
    print('Closing ${_outboundStreams.length} persistent streams...');
    final closeOperations = <Future>[];
    for (final entry in _outboundStreams.entries) {
      closeOperations.add(
        entry.value.close().catchError((e) {
          print('Error closing stream to ${entry.key}: $e');
        })
      );
    }
    await Future.wait(closeOperations);
    _outboundStreams.clear();

    // Unregister protocol handlers from the host
    _host.removeStreamHandler(gossipSubIDv11);
    // TODO: Unregister for other protocols if registered.
    print('PubSubProtocol closed and stream handler for $gossipSubIDv11 unregistered.');
  }
}

// Helper extension for short string representation of RPC for logging.
extension RpcShortString on pb.RPC {
  String toShortString() {
    final parts = <String>[];
    if (this.hasControl()) parts.add('CTL');
    if (this.publish.isNotEmpty) parts.add('PUB(${this.publish.length})');
    if (this.subscriptions.isNotEmpty) parts.add('SUB(${this.subscriptions.length})');
    return parts.isEmpty ? 'RPC(empty)' : 'RPC(${parts.join(',')})';
  }
}

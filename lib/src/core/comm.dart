import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/network/context.dart' as p2p_context;
import 'package:dart_libp2p/p2p/transport/multiplexing/yamux/yamux_exceptions.dart';
import 'package:dart_libp2p/p2p/protocol/identify/identify_exceptions.dart';
import 'package:dart_libp2p/utils/varint.dart';

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
  void Function(PeerId peerId)? onNewInboundPeer;

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

  /// Internal handler for new inbound streams.
  /// Reads multiple varint-length-prefixed RPC messages on a persistent stream.
  Future<void> _handleNewStreamData(P2PStream stream, PeerId remotePeer) async {
    print('Received incoming PubSub stream ${stream.id()} from $remotePeer on protocol ${stream.protocol()}');
    // Notify about new peer so we can send our subscriptions
    onNewInboundPeer?.call(remotePeer);
    final carryOver = <int>[];
    try {
      while (!stream.isClosed && !_isClosing) {
        final bytes = await _readVarintPrefixed(stream, carryOver);
        if (bytes == null) break; // Stream closed cleanly
        final rpc = pb.RPC.fromBuffer(bytes);
        await _onRpcReceived(remotePeer, rpc);
      }
    } catch (e, s) {
      if (!_isClosing) {
        print('Error on inbound PubSub stream from $remotePeer: $e');
      }
    } finally {
      if (!stream.isClosed) {
        await stream.close();
      }
    }
  }

  /// Reads a single varint-length-prefixed message from the stream.
  /// Returns null if the stream is closed before any data is read.
  Future<Uint8List?> _readVarintPrefixed(P2PStream stream, List<int> carryOver) async {
    // Read varint length prefix
    final varintBytes = BytesBuilder(copy: false);
    while (true) {
      int byte;
      if (carryOver.isNotEmpty) {
        byte = carryOver.removeAt(0);
      } else {
        final chunk = await stream.read(12);
        if (chunk.isEmpty) return null; // Stream closed
        carryOver.addAll(chunk);
        byte = carryOver.removeAt(0);
      }
      varintBytes.addByte(byte);
      if ((byte & 0x80) == 0) break; // End of varint
      if (varintBytes.length > 10) {
        throw FormatException('Varint too long');
      }
    }

    final msgLen = decodeVarint(varintBytes.toBytes());
    if (msgLen == 0) return Uint8List(0);

    // Read message bytes
    final result = BytesBuilder(copy: false);
    // Use carry-over first
    if (carryOver.isNotEmpty) {
      final take = carryOver.length > msgLen ? msgLen : carryOver.length;
      result.add(carryOver.sublist(0, take));
      final remaining = carryOver.sublist(take);
      carryOver.clear();
      carryOver.addAll(remaining);
    }
    while (result.length < msgLen) {
      final chunk = await stream.read(msgLen - result.length);
      if (chunk.isEmpty) throw StateError('Stream closed mid-message');
      result.add(chunk);
    }
    // Handle over-read
    final built = result.toBytes();
    if (built.length > msgLen) {
      carryOver.addAll(built.sublist(msgLen));
      return Uint8List.sublistView(built, 0, msgLen);
    }
    return built;
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

        // Encode with varint length prefix (matches go-libp2p-pubsub msgio framing)
        final msgBytes = rpc.writeToBuffer();
        final lengthPrefix = encodeVarint(msgBytes.length);
        final framed = BytesBuilder(copy: false);
        framed.add(lengthPrefix);
        framed.add(msgBytes);
        await persistentStream.stream.write(framed.toBytes());

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

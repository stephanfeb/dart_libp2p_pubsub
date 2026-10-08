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
import 'validation.dart' show defaultMaxMessageSize;
import 'package:logging/logging.dart';

final _log = Logger('PubSubComm');

// Protocol IDs, as go-libp2p-pubsub.
const String gossipSubIDv10 = '/meshsub/1.0.0';
const String gossipSubIDv11 = '/meshsub/1.1.0';
const String gossipSubIDv12 = '/meshsub/1.2.0';
const String gossipSubIDv13 = '/meshsub/1.3.0';
const String floodSubID = '/floodsub/1.0.0';
const String randomSubID = '/randomsub/1.0.0';

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

  /// Whether an RPC was written on the stream, or is being written.
  bool firstRpcSent = false;

  /// The end of the chain of writes on this stream.
  Future<void> _lastWrite = Future.value();

  /// Writes [data] after the previous writes on this stream complete. A
  /// frame is written in several parts by the muxer, so writes must not
  /// overlap or frames would interleave.
  Future<void> write(Uint8List data) {
    final previous = _lastWrite;
    final done = Completer<void>();
    _lastWrite = done.future;
    return previous.then((_) => stream.write(data)).whenComplete(done.complete);
  }

  /// Closes the stream, waiting at most [timeout] (see [closeStream]).
  Future<void> close(Duration timeout) async {
    if (!_isClosed) {
      _isClosed = true;
      await closeStream(stream, timeout);
    }
  }
}

/// How long [PubSubProtocol] waits for a stream to close before resetting it.
const Duration defaultStreamCloseTimeout = Duration(seconds: 2);

/// Closes [stream], waiting at most [timeout], and resets it if the close
/// fails or takes longer. Never throws.
///
/// Closing sends a FIN behind any data already queued on the connection, so
/// it waits for a slow or stalled remote to read that data; without a limit,
/// one such peer would hold up [PubSubProtocol.close] forever. The reset is
/// not awaited, as it can wait on the same connection.
Future<void> closeStream(P2PStream stream, Duration timeout) async {
  try {
    await stream.close().timeout(timeout);
  } catch (e) {
    _log.fine('Stream ${stream.id()} did not close cleanly ($e); resetting it');
    try {
      stream.reset().catchError((Object e) {
        _log.fine('Error resetting stream ${stream.id()}: $e');
      });
    } catch (e) {
      _log.fine('Error resetting stream ${stream.id()}: $e');
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
  /// Called for each inbound pubsub stream, with the peer and the stream's
  /// protocol.
  void Function(PeerId peerId, String protocol)? onNewInboundPeer;

  /// Called when a peer ends our stream to it, as go-libp2p-pubsub's
  /// `handlePeerDead`: the peer stopped its pubsub, or the stream failed.
  void Function(PeerId peerId)? onPeerDead;

  /// Called with the first RPC written on each new outbound stream and the
  /// stream's protocol; the RPC it returns is written instead. GossipSub
  /// v1.3 adds its extensions to the first RPC this way, as
  /// go-libp2p-pubsub does to the hello packet.
  pb.RPC Function(PeerId peerId, String protocol, pb.RPC rpc)? onFirstRpc;

  /// Map of persistent outbound streams per peer
  final Map<PeerId, _PersistentStream> _outboundStreams = {};

  /// Lock for managing stream creation per peer
  final Map<PeerId, Completer<_PersistentStream>> _streamCreationLocks = {};

  /// The protocols we speak, in order of preference. Inbound streams are
  /// accepted on each; outbound streams negotiate one of them.
  final List<String> protocols;

  /// The protocol negotiated on the outbound stream to each peer.
  final Map<PeerId, String> _negotiated = {};

  bool _isClosing = false;

  /// The inbound streams being read, closed by [close].
  final Set<P2PStream> _inboundStreams = {};

  /// How long to wait for a stream to close before resetting it.
  final Duration streamCloseTimeout;

  /// The maximum size of one RPC, in bytes, in either direction (as
  /// go-libp2p-pubsub's `WithMaxMessageSize`). A peer that sends a larger
  /// frame has its stream reset; [sendRpc] refuses to send a larger RPC.
  final int maxMessageSize;

  /// Creates a new [PubSubProtocol] instance.
  ///
  /// [_host] is the libp2p Host.
  /// [_onRpcReceived] is a callback function that will be invoked when a new
  /// RPC message is received from a peer.
  PubSubProtocol(this._host, this._onRpcReceived,
      {this.maxMessageSize = defaultMaxMessageSize,
      this.protocols = const [gossipSubIDv11],
      this.streamCloseTimeout = defaultStreamCloseTimeout}) {
    start();
  }

  /// Registers the stream handlers of [protocols]. The constructor calls it;
  /// call it again to reopen after [close].
  void start() {
    _isClosing = false;
    for (final protocol in protocols) {
      _host.setStreamHandler(protocol, _handleNewStreamData);
    }
    _log.fine('PubSubProtocol started with persistent streams for $protocols.');
  }

  /// The protocol negotiated with [peerId] on our stream to it, if open.
  String? protocolOf(PeerId peerId) => _negotiated[peerId];

  /// Internal handler for new inbound streams.
  /// Reads multiple varint-length-prefixed RPC messages on a persistent stream.
  Future<void> _handleNewStreamData(P2PStream stream, PeerId remotePeer) async {
    _log.fine('Received incoming PubSub stream ${stream.id()} from $remotePeer on protocol ${stream.protocol()}');
    // Notify about new peer so we can send our subscriptions
    onNewInboundPeer?.call(remotePeer, stream.protocol());
    final carryOver = <int>[];
    var failed = false;
    _inboundStreams.add(stream);
    try {
      while (!stream.isClosed && !_isClosing) {
        final bytes = await _readVarintPrefixed(stream, carryOver);
        if (bytes == null) break; // Stream closed cleanly
        final rpc = pb.RPC.fromBuffer(bytes);
        // As in go-libp2p-pubsub, reading does not wait for the RPC to be
        // handled: the router handles control messages synchronously and
        // validates messages concurrently (see Router.handleRpc).
        _onRpcReceived(remotePeer, rpc).catchError((Object e, StackTrace s) {
          _log.warning('Error handling RPC from $remotePeer: $e\n$s');
        });
      }
    } catch (e) {
      failed = true;
      if (!_isClosing) {
        _log.fine('Error on inbound PubSub stream from $remotePeer: $e');
      }
    } finally {
      _inboundStreams.remove(stream);
      if (!stream.isClosed) {
        // As in go-libp2p-pubsub, a stream that failed (an oversized or
        // malformed frame) is reset rather than closed.
        if (failed) {
          try {
            await stream.reset();
          } catch (e) {
            _log.fine('Error resetting inbound PubSub stream from $remotePeer: $e');
          }
        } else {
          await closeStream(stream, streamCloseTimeout);
        }
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
    // As go-libp2p-pubsub's msgio reader: refuse a frame larger than the
    // maximum before reading it, so a peer cannot make us buffer it.
    if (msgLen < 0 || msgLen > maxMessageSize) {
      throw FormatException('RPC of $msgLen bytes exceeds the maximum of $maxMessageSize bytes');
    }

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
      _log.fine('Removed closed stream for peer $peerId');
    }

    // Check if another call is already creating a stream for this peer
    final lock = _streamCreationLocks[peerId];
    if (lock != null && !lock.isCompleted) {
      _log.fine('Waiting for concurrent stream creation for peer $peerId');
      return await lock.future;
    }

    // Create new lock for this stream creation
    final newLock = Completer<_PersistentStream>();
    // The lock is completed with the error of a failed stream creation. When
    // no concurrent caller waits on it, that error must not be reported as
    // uncaught, which would terminate the isolate.
    newLock.future.ignore();
    _streamCreationLocks[peerId] = newLock;

    try {
      _log.fine('Creating new persistent stream to $peerId on $protocols');
      final stream = await _host.newStream(peerId, protocols, p2p_context.Context());
      if (_isClosing) {
        // Closed while the stream was opening: close() did not see it.
        unawaited(closeStream(stream, streamCloseTimeout));
        throw StateError('PubSubProtocol closed while opening a stream to $peerId');
      }
      _negotiated[peerId] = stream.protocol();

      final persistentStream = _PersistentStream(
        stream: stream,
        peerId: peerId,
      );

      _outboundStreams[peerId] = persistentStream;
      _watchOutbound(persistentStream);
      newLock.complete(persistentStream);
      _log.fine('Created persistent stream to $peerId (stream id: ${stream.id()})');

      return persistentStream;
    } on IdentifyTimeoutException catch (e, s) {
      // Handle identify timeout gracefully - this is a recoverable error.
      // The peer may have gone offline or be temporarily unreachable.
      newLock.completeError(e, s);
      _log.fine('PubSubProtocol: Identify timeout creating stream to $peerId. Peer may be unreachable: $e');
      rethrow;
    } on IdentifyException catch (e, s) {
      // Handle other identify exceptions
      newLock.completeError(e, s);
      _log.fine('PubSubProtocol: Identify error creating stream to $peerId: $e');
      rethrow;
    } catch (e, s) {
      newLock.completeError(e, s);
      _log.fine('Failed to create stream to $peerId: $e');
      rethrow;
    } finally {
      _streamCreationLocks.remove(peerId);
    }
  }

  /// Waits for the peer to end our stream to it, as go-libp2p-pubsub's
  /// `handlePeerDead`: the peer never writes on it, so a read returns only
  /// when the stream ends (or on unexpected data). The stream is then reset
  /// and [onPeerDead] called, unless we closed or replaced the stream.
  void _watchOutbound(_PersistentStream persistent) {
    final peerId = persistent.peerId;
    Future.sync(persistent.stream.read).then((data) {
      if (data.isNotEmpty) _log.fine('Unexpected data from $peerId on our stream to it');
    }, onError: (Object e) {
      _log.fine('Our stream to $peerId failed: $e');
    }).whenComplete(() {
      if (!identical(_outboundStreams[peerId], persistent)) return; // Closed by us.
      _outboundStreams.remove(peerId);
      _negotiated.remove(peerId);
      persistent._isClosed = true;
      persistent.stream.reset().catchError((Object e) {
        _log.fine('Error resetting the stream to $peerId: $e');
      });
      if (!_isClosing) onPeerDead?.call(peerId);
    });
  }

  /// Sends an RPC message to a specific peer using a persistent stream.
  ///
  /// [peerId] is the recipient peer.
  /// [rpc] is the RPC message to send.
  /// [protocolId] is kept for compatibility: a new stream negotiates one of
  /// [protocols] (see [protocolOf]).
  Future<void> sendRpc(PeerId peerId, pb.RPC rpc, String protocolId) async {
    _log.fine('Attempting to send RPC to $peerId on protocol $protocolId: ${rpc.toShortString()}');
    
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
          _log.fine('Stream to $peerId not writable, removing from cache');
          _outboundStreams.remove(peerId);
          if (attempt == 0) {
            continue; // Retry with fresh stream
          }
          throw StateError('Stream to $peerId not writable after retry');
        }

        var toSend = rpc;
        if (!persistentStream.firstRpcSent) {
          // Set before any await, so that only this RPC goes first; writes
          // are made in the order they are started.
          persistentStream.firstRpcSent = true;
          toSend = onFirstRpc?.call(peerId, persistentStream.stream.protocol(), rpc) ?? rpc;
        }

        // Encode with varint length prefix (matches go-libp2p-pubsub msgio framing)
        final msgBytes = toSend.writeToBuffer();
        if (msgBytes.length > maxMessageSize) {
          // A peer would reset the stream on this frame. Callers split large
          // RPCs with splitRpc first.
          throw RpcTooLargeException(msgBytes.length, maxMessageSize);
        }
        final lengthPrefix = encodeVarint(msgBytes.length);
        final framed = BytesBuilder(copy: false);
        framed.add(lengthPrefix);
        framed.add(msgBytes);
        await persistentStream.write(framed.toBytes());

        _log.fine('RPC sent to $peerId on persistent stream successfully.');
        return; // Success
        
      } on YamuxStreamStateException catch (e) {
        // Stream state error - retry once with fresh stream
        if (attempt == 0) {
          _log.fine('Stream to $peerId in state ${e.currentState}, removing and retrying...');
          final stream = _outboundStreams.remove(peerId);
          if (stream != null) {
            await stream.close(streamCloseTimeout);
          }
          continue; // Retry
        }
        
        // Second attempt failed, clean up and rethrow
        _log.fine('Failed to send RPC to $peerId after retry: ${e.message}');
        _outboundStreams.remove(peerId);
        rethrow;
        
      } on RpcTooLargeException {
        rethrow; // The stream is fine; only this RPC is refused.
      } on IdentifyTimeoutException catch (e) {
        // Identify timeout - peer may have gone offline. Handle gracefully.
        _log.fine('PubSubProtocol: Identify timeout sending RPC to $peerId. Peer unreachable: $e');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close(streamCloseTimeout);
        }
        // Don't rethrow - this is a recoverable error that the RPC queue will handle
        rethrow;
      } on IdentifyException catch (e, s) {
        // Other identify error - handle gracefully
        _log.fine('PubSubProtocol: Identify error sending RPC to $peerId: $e\n$s');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close(streamCloseTimeout);
        }
        rethrow;
      } catch (e, s) {
        // Any other exception type - don't retry, just fail
        _log.fine('Error sending RPC to $peerId on $protocolId: $e\n$s');
        final stream = _outboundStreams.remove(peerId);
        if (stream != null) {
          await stream.close(streamCloseTimeout);
        }
        rethrow;
      }
    }
  }

  /// Closes the persistent stream to a peer (e.g., when peer disconnects).
  Future<void> closePeerStream(PeerId peerId) async {
    _negotiated.remove(peerId);
    final stream = _outboundStreams.remove(peerId);
    if (stream != null) {
      _log.fine('Closing persistent stream to $peerId');
      await stream.close(streamCloseTimeout);
    }
  }

  /// Unregisters the stream handlers and closes all streams. [start]
  /// reopens.
  Future<void> close() async {
    _isClosing = true;

    // Close all streams. Each close is bounded by streamCloseTimeout, so a
    // stalled peer cannot hold up the others or the caller. Closing an
    // inbound stream ends its read loop.
    _log.fine('Closing ${_outboundStreams.length} outbound and '
        '${_inboundStreams.length} inbound streams...');
    final outbound = _outboundStreams.values.toList();
    final inbound = _inboundStreams.toList();
    _outboundStreams.clear();
    _inboundStreams.clear();
    _negotiated.clear();
    await Future.wait([
      for (final stream in outbound) stream.close(streamCloseTimeout),
      for (final stream in inbound) closeStream(stream, streamCloseTimeout),
    ]);

    // Unregister protocol handlers from the host
    for (final protocol in protocols) {
      _host.removeStreamHandler(protocol);
    }
    _log.fine('PubSubProtocol closed and stream handlers for $protocols unregistered.');
  }
}

/// Thrown by [PubSubProtocol.sendRpc] for an RPC larger than
/// [PubSubProtocol.maxMessageSize].
class RpcTooLargeException implements Exception {
  final int size;
  final int limit;
  RpcTooLargeException(this.size, this.limit);
  @override
  String toString() => 'RpcTooLargeException: RPC of $size bytes exceeds the maximum of $limit bytes';
}

/// Splits [rpc] into RPCs of at most [limit] bytes each, as go-libp2p-pubsub's
/// `RPC.split`: the published messages first, then the subscriptions and the
/// control messages. An item that is larger than [limit] on its own is
/// returned in an RPC of its own, which is still too large; the caller drops
/// it.
List<pb.RPC> splitRpc(pb.RPC rpc, int limit) {
  if (rpc.writeToBuffer().length <= limit) return [rpc];
  final parts = <pb.RPC>[];

  // Published messages: sized incrementally (field tag + length + body).
  var next = pb.RPC();
  var nextSize = 0;
  for (final msg in rpc.publish) {
    final size = _embeddedSize(msg.writeToBuffer().length);
    if (nextSize > 0 && nextSize + size > limit) {
      parts.add(next);
      next = pb.RPC();
      nextSize = 0;
    }
    next.publish.add(msg);
    nextSize += size;
  }
  if (nextSize > 0) parts.add(next);

  // Everything else.
  final rest = pb.RPC()..subscriptions.addAll(rpc.subscriptions);
  if (rpc.hasControl()) rest.control = rpc.control;
  if (rest.writeToBuffer().isEmpty) return parts;
  if (rest.writeToBuffer().length <= limit) return parts..add(rest);

  next = pb.RPC();
  var items = 0; // Items in next.
  void add(void Function(pb.RPC) put, void Function(pb.RPC) undo) {
    put(next);
    if (items > 0 && next.writeToBuffer().length > limit) {
      undo(next);
      parts.add(next);
      next = pb.RPC();
      put(next);
      items = 0;
    }
    items++;
  }

  for (final sub in rpc.subscriptions) {
    add((r) => r.subscriptions.add(sub), (r) => r.subscriptions.removeLast());
  }
  if (rpc.hasControl()) {
    final ctl = rpc.control;
    for (final graft in ctl.graft) {
      add((r) => r.ensureControl().graft.add(graft), (r) => r.ensureControl().graft.removeLast());
    }
    for (final prune in ctl.prune) {
      add((r) => r.ensureControl().prune.add(prune), (r) => r.ensureControl().prune.removeLast());
    }
    // IHAVE, IWANT and IDONTWANT can carry many IDs: split them per ID.
    for (final ihave in ctl.ihave) {
      for (final id in ihave.messageIDs) {
        add((r) {
          final c = r.ensureControl();
          if (c.ihave.isEmpty || c.ihave.last.topicID != ihave.topicID) {
            c.ihave.add(pb.ControlIHave()..topicID = ihave.topicID);
          }
          c.ihave.last.messageIDs.add(id);
        }, (r) {
          final last = r.ensureControl().ihave.last;
          last.messageIDs.removeLast();
          if (last.messageIDs.isEmpty) r.ensureControl().ihave.removeLast();
        });
      }
    }
    for (final iwant in ctl.iwant) {
      for (final id in iwant.messageIDs) {
        add((r) {
          final c = r.ensureControl();
          if (c.iwant.isEmpty) c.iwant.add(pb.ControlIWant());
          c.iwant.last.messageIDs.add(id);
        }, (r) {
          final last = r.ensureControl().iwant.last;
          last.messageIDs.removeLast();
          if (last.messageIDs.isEmpty) r.ensureControl().iwant.removeLast();
        });
      }
    }
    for (final idontwant in ctl.idontwant) {
      for (final id in idontwant.messageIDs) {
        add((r) {
          final c = r.ensureControl();
          if (c.idontwant.isEmpty) c.idontwant.add(pb.ControlIDontWant());
          c.idontwant.last.messageIDs.add(id);
        }, (r) {
          final last = r.ensureControl().idontwant.last;
          last.messageIDs.removeLast();
          if (last.messageIDs.isEmpty) r.ensureControl().idontwant.removeLast();
        });
      }
    }
  }
  if (items > 0) parts.add(next);
  return parts;
}

/// The size of an embedded message field (number < 16) with a body of
/// [bodySize] bytes.
int _embeddedSize(int bodySize) => 1 + encodeVarint(bodySize).length + bodySize;

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

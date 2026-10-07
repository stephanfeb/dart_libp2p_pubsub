import 'dart:async';
import 'dart:collection';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/comm.dart';
import 'package:logging/logging.dart';

final _log = Logger('RpcQueue');

/// The default maximum number of RPCs queued for one peer
/// (go-libp2p-pubsub's `peerOutboundQueueSize`).
const int defaultPeerOutboundQueueSize = 32;

/// The outgoing RPCs of one peer, as go-libp2p-pubsub's `rpcQueue`: a
/// bounded queue with a priority lane, sent one at a time.
class PeerRpcQueue {
  final PeerId peerId;
  final PubSubProtocol comms;
  final String protocolId;

  /// The maximum number of queued RPCs, both lanes together.
  final int maxSize;

  final Queue<pb.RPC> _normal = Queue<pb.RPC>();
  final Queue<pb.RPC> _priority = Queue<pb.RPC>();
  bool _isSending = false;

  PeerRpcQueue(this.peerId, this.comms, this.protocolId, {this.maxSize = defaultPeerOutboundQueueSize});

  /// Queues [rpc]; [urgent] RPCs are sent before the others. Returns false,
  /// without queueing, when the queue is full.
  bool add(pb.RPC rpc, {bool urgent = false}) {
    if (length >= maxSize) {
      _log.fine('PeerRpcQueue ($peerId): queue full ($maxSize); dropping ${rpc.toShortString()}.');
      return false;
    }
    (urgent ? _priority : _normal).addLast(rpc);
    if (!_isSending) {
      // The send loop catches its errors, so nothing escapes this future.
      unawaited(_sendLoop());
    }
    return true;
  }

  Future<void> _sendLoop() async {
    _isSending = true;
    try {
      while (length > 0) {
        final rpc = _priority.isNotEmpty ? _priority.removeFirst() : _normal.removeFirst();
        try {
          await comms.sendRpc(peerId, rpc, protocolId);
        } catch (e) {
          // The RPC is dropped; the next one tries a new stream. A peer that
          // cannot be reached at all is removed when it disconnects.
          _log.fine('PeerRpcQueue ($peerId): dropping ${rpc.toShortString()} after a send error: $e');
        }
      }
    } finally {
      _isSending = false;
    }
  }

  /// Clears the queue for this peer.
  void clear() {
    _normal.clear();
    _priority.clear();
  }

  int get length => _normal.length + _priority.length;
}

/// The outgoing RPC queues of all peers.
class RpcOutgoingQueueManager {
  final PubSubProtocol _comms;
  final String _defaultProtocolId;
  final int _maxQueueSize;
  final Map<PeerId, PeerRpcQueue> _peerQueues = {};

  RpcOutgoingQueueManager(this._comms, this._defaultProtocolId,
      {int maxQueueSize = defaultPeerOutboundQueueSize})
      : _maxQueueSize = maxQueueSize;

  /// Queues [rpc] for [peerId], as go-libp2p-pubsub's `sendRPC`. An RPC
  /// larger than the comms' maximum message size is split into several
  /// RPCs (see [splitRpc]). Returns each part with whether it was queued: a
  /// part is dropped if it is still too large (one oversized message) or if
  /// the queue is full.
  List<(pb.RPC, bool)> sendRpc(PeerId peerId, pb.RPC rpc, {String? protocolId, bool urgent = false}) {
    final limit = _comms.maxMessageSize;
    return [
      for (final part in splitRpc(rpc, limit)) (part, _enqueue(peerId, part, limit, protocolId, urgent)),
    ];
  }

  bool _enqueue(PeerId peerId, pb.RPC part, int limit, String? protocolId, bool urgent) {
    final size = part.writeToBuffer().length;
    if (size > limit) {
      _log.fine('RpcOutgoingQueueManager: Dropping oversized RPC to $peerId ($size bytes, limit $limit).');
      return false;
    }
    final queue = _peerQueues.putIfAbsent(
        peerId, () => PeerRpcQueue(peerId, _comms, protocolId ?? _defaultProtocolId, maxSize: _maxQueueSize));
    return queue.add(part, urgent: urgent);
  }

  /// Removes and clears the queue for a peer (e.g., when a peer disconnects).
  void peerDisconnected(PeerId peerId) {
    _peerQueues.remove(peerId)?.clear();
  }

  /// Clears all RPC queues.
  void clearAll() {
    for (final queue in _peerQueues.values) {
      queue.clear();
    }
    _peerQueues.clear();
  }
}

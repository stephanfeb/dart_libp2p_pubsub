import 'dart:async';
import 'dart:collection';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/comm.dart'; // For PubSubProtocol and gossipSubIDv11 (or other protocol IDs)

// TODO: Define configuration parameters for the RPC queue, e.g., max queue size, send concurrency.

/// Manages a queue of outgoing RPC messages for a specific peer.
///
/// This helps in scenarios where a peer might be slow to process messages or if
/// we want to control the rate of sending RPCs to a peer.
class PeerRpcQueue {
  final PeerId peerId;
  final PubSubProtocol comms; // To send the actual RPCs
  final String protocolId; // The protocol ID to use for sending (e.g., gossipSubIDv11)

  final Queue<pb.RPC> _queue = Queue<pb.RPC>();
  bool _isSending = false;
  // TODO: Add rate limiting, backpressure, max queue size logic.

  PeerRpcQueue(this.peerId, this.comms, this.protocolId);

  /// Adds an RPC message to the queue for sending.
  void add(pb.RPC rpc) {
    // TODO: Check against max queue size.
    print('[DEBUG] PeerRpcQueue ($peerId): add() called with ${rpc.toShortString()}. Queue length before: ${_queue.length}, _isSending: $_isSending');
    _queue.addLast(rpc);
    print('[DEBUG] PeerRpcQueue ($peerId): add() after addLast. Queue length: ${_queue.length}');
    _trySend();
  }

  Future<void> _trySend() async {
    print('[DEBUG] PeerRpcQueue ($peerId): _trySend() called. _isSending: $_isSending, queue empty: ${_queue.isEmpty}');
    if (_isSending || _queue.isEmpty) {
      if(_isSending) print('[DEBUG] PeerRpcQueue ($peerId): _trySend() returning because _isSending is true.');
      if(_queue.isEmpty) print('[DEBUG] PeerRpcQueue ($peerId): _trySend() returning because queue is empty.');
      return;
    }
    _isSending = true;
    print('[DEBUG] PeerRpcQueue ($peerId): _trySend() set _isSending = true. Starting loop.');

    while (_queue.isNotEmpty) {
      final rpc = _queue.first; // Peek at the first message
      print('[DEBUG] PeerRpcQueue ($peerId): Loop iteration. Queue length: ${_queue.length}. Processing ${rpc.toShortString()}');
      try {
        print('[DEBUG] PeerRpcQueue ($peerId): Attempting to send from queue: ${rpc.toShortString()} with protocol $protocolId');
        // print('PeerRpcQueue ($peerId): Sending RPC: ${rpc.toShortString()}');
        await comms.sendRpc(peerId, rpc, protocolId);
        _queue.removeFirst(); // Successfully sent, remove from queue
        print('[DEBUG] PeerRpcQueue ($peerId): Successfully sent ${rpc.toShortString()} and removed from queue. Queue length now: ${_queue.length}');
      } catch (e, s) { // Added stack trace to catch
        print('[DEBUG] PeerRpcQueue ($peerId): CAUGHT ERROR sending RPC: $e. Stack: $s. Message ${rpc.toShortString()} remains in queue. Stopping send loop.');
        // TODO: Implement retry logic, backoff, or error handling (e.g., drop message, notify router).
        // For now, we stop sending to this peer on error to avoid hammering.
        _isSending = false;
        return;
      }
      // TODO: Add delay or rate limiting if needed.
    }
    _isSending = false;
    print('[DEBUG] PeerRpcQueue ($peerId): _trySend() loop finished (queue empty). Set _isSending = false.');
  }

  /// Clears the queue for this peer.
  void clear() {
    _queue.clear();
  }

  int get length => _queue.length;
}

/// Manages RPC queues for all peers.
///
/// This class holds a map of [PeerRpcQueue] instances, one for each peer
/// we are sending RPCs to.
class RpcOutgoingQueueManager {
  final PubSubProtocol _comms;
  final String _defaultProtocolId; // e.g., gossipSubIDv11
  final Map<PeerId, PeerRpcQueue> _peerQueues = {};

  RpcOutgoingQueueManager(this._comms, this._defaultProtocolId);

  /// Enqueues an RPC to be sent to a specific peer.
  ///
  /// If a queue for the peer doesn't exist, it's created.
  void sendRpc(PeerId peerId, pb.RPC rpc, {String? protocolId}) {
    final effectiveProtocolId = protocolId ?? _defaultProtocolId;
    final queue = _peerQueues.putIfAbsent(
      peerId,
      () => PeerRpcQueue(peerId, _comms, effectiveProtocolId),
    );
    // Ensure the queue is using the potentially updated protocolId if specified
    // This simple model assumes protocolId per peer queue is fixed on creation.
    // If protocolId can change per RPC for the same peer, PeerRpcQueue needs adjustment.
    if (queue.protocolId != effectiveProtocolId && protocolId != null) {
       print('RpcOutgoingQueueManager: Warning - trying to send RPC to $peerId with different protocol ID (${queue.protocolId} vs $effectiveProtocolId). Using existing queue protocol.');
       // Or, create a new queue for the different protocol, or make PeerRpcQueue handle multiple protocols.
       // For now, we stick to the queue's initial protocol.
    }

    queue.add(rpc);
  }

  /// Removes and clears the queue for a peer (e.g., when a peer disconnects).
  void peerDisconnected(PeerId peerId) {
    final queue = _peerQueues.remove(peerId);
    queue?.clear();
    print('RpcOutgoingQueueManager: Cleared RPC queue for disconnected peer $peerId.');
  }

  /// Clears all RPC queues.
  void clearAll() {
    _peerQueues.forEach((_, queue) => queue.clear());
    _peerQueues.clear();
    print('RpcOutgoingQueueManager: All RPC queues cleared.');
  }

  // TODO: Add methods for managing queue parameters, stats, etc.
}

import 'dart:async';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/network.dart';
import 'package:dart_libp2p/core/network/notifiee.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

final _log = Logger('PeerNotifier');

/// Callback function type for when a peer connects that is relevant to PubSub.
typedef PeerConnectedCallback = FutureOr<void> Function(PeerId peerId);

/// Callback function type for when a peer disconnects that is relevant to PubSub.
typedef PeerDisconnectedCallback = FutureOr<void> Function(PeerId peerId);

/// Tells PubSub when peers connect and disconnect, from the notifications of
/// the host's network.
///
/// The connected callbacks run for each new connection to a peer, so they can
/// run more than once for a peer: when two peers dial each other at the same
/// time, the network can report both connections after both are open, and
/// waiting for the first one could miss the peer. The disconnected callbacks
/// run when the last connection to a peer closes. Callbacks must accept being
/// called again for the same peer.
///
/// The network of dart_libp2p does not report every closed connection: a
/// connection closed with `Network.closePeer` or by the remote peer can go
/// unreported. Users should not rely on the disconnected callbacks alone.
class PeerNotifier {
  final Network _network;
  late final Notifiee _notifiee;

  final List<PeerConnectedCallback> _connectedCallbacks = [];
  final List<PeerDisconnectedCallback> _disconnectedCallbacks = [];

  /// Starts listening to the network of [host]. Call [dispose] to stop.
  PeerNotifier(Host host) : _network = host.network {
    _notifiee = NotifyBundle(
      connectedF: (network, conn, {Duration? dialLatency}) {
        _notifyConnected(conn.remotePeer);
      },
      disconnectedF: (network, conn) {
        final peerId = conn.remotePeer;
        // The peer is gone when its last connection closes.
        if (network.connsToPeer(peerId).isNotEmpty) return;
        _notifyDisconnected(peerId);
      },
    );
    _network.notify(_notifiee);
  }

  /// Registers a callback to be invoked when a relevant peer connects.
  void onPeerConnected(PeerConnectedCallback callback) {
    _connectedCallbacks.add(callback);
  }

  /// Registers a callback to be invoked when a relevant peer disconnects.
  void onPeerDisconnected(PeerDisconnectedCallback callback) {
    _disconnectedCallbacks.add(callback);
  }

  Future<void> _notifyConnected(PeerId peerId) async {
    _log.fine('PeerNotifier: Peer connected - ${peerId.toBase58()}');
    for (final callback in List.of(_connectedCallbacks)) {
      try {
        await callback(peerId);
      } catch (e, s) {
        _log.warning('PeerNotifier: Error in onPeerConnected callback for $peerId: $e\n$s');
      }
    }
  }

  Future<void> _notifyDisconnected(PeerId peerId) async {
    _log.fine('PeerNotifier: Peer disconnected - ${peerId.toBase58()}');
    for (final callback in List.of(_disconnectedCallbacks)) {
      try {
        await callback(peerId);
      } catch (e, s) {
        _log.warning('PeerNotifier: Error in onPeerDisconnected callback for $peerId: $e\n$s');
      }
    }
  }

  /// Stops listening to the network and removes the callbacks.
  void dispose() {
    _network.stopNotify(_notifiee);
    _connectedCallbacks.clear();
    _disconnectedCallbacks.clear();
    _log.fine('PeerNotifier: Disposed.');
  }
}

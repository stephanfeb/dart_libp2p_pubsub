import 'dart:async';
import 'package:dart_libp2p/core/interfaces.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart'; // For Host, to potentially access event bus
// It's likely that the Host's event bus or connection manager will emit specific event types.
// For example: import 'package:dart_libp2p/core/event/events.dart';

/// Callback function type for when a peer connects that is relevant to PubSub.
typedef PeerConnectedCallback = FutureOr<void> Function(PeerId peerId);

/// Callback function type for when a peer disconnects that is relevant to PubSub.
typedef PeerDisconnectedCallback = FutureOr<void> Function(PeerId peerId);

// TODO: Consider other notification types if needed, e.g., for peer tagging
// as in go-libp2p-pubsub's PeerTaggerNotifee.

/// Manages peer event notifications for PubSub.
///
/// This class would typically subscribe to the libp2p Host's event bus
/// or connection manager events and dispatch them to registered PubSub-specific
/// callbacks.
class PeerNotifier {
  final Host _host; // To access event bus or connection manager

  final List<PeerConnectedCallback> _connectedCallbacks = [];
  final List<PeerDisconnectedCallback> _disconnectedCallbacks = [];

  // StreamSubscription for listening to host events (placeholder)
  // StreamSubscription? _hostEventSubscription;

  PeerNotifier(this._host) {
    _listenToHostEvents();
  }

  void _listenToHostEvents() {
    final changeSub = _host.eventBus.subscribe(EvtPeerConnectednessChanged);

    changeSub.stream.listen((event){
      if (event is EvtPeerConnectednessChanged && event.connectedness == Connectedness.notConnected) {
        _notifyDisconnected(event.peer);
      }else if (event is EvtPeerConnectednessChanged && event.connectedness == Connectedness.connected){
        _notifyConnected(event.peer);
      }
    });


    print('PeerNotifier: TODO: Implement actual subscription to host peer events.');
  }

  /// Registers a callback to be invoked when a relevant peer connects.
  void onPeerConnected(PeerConnectedCallback callback) {
    _connectedCallbacks.add(callback);
  }

  /// Registers a callback to be invoked when a relevant peer disconnects.
  void onPeerDisconnected(PeerDisconnectedCallback callback) {
    _disconnectedCallbacks.add(callback);
  }

  /// Notifies all registered callbacks about a peer connection.
  /// This would be called internally when a relevant host event is received.
  Future<void> _notifyConnected(PeerId peerId) async {
    print('PeerNotifier: Peer connected - ${peerId.toBase58()}');
    for (final callback in _connectedCallbacks) {
      try {
        await callback(peerId);
      } catch (e, s) {
        print('PeerNotifier: Error in onPeerConnected callback for $peerId: $e\n$s');
      }
    }
  }

  /// Notifies all registered callbacks about a peer disconnection.
  /// This would be called internally when a relevant host event is received.
  Future<void> _notifyDisconnected(PeerId peerId) async {
    print('PeerNotifier: Peer disconnected - ${peerId.toBase58()}');
    for (final callback in _disconnectedCallbacks) {
      try {
        await callback(peerId);
      } catch (e, s) {
        print('PeerNotifier: Error in onPeerDisconnected callback for $peerId: $e\n$s');
      }
    }
  }

  /// Disposes of the notifier, cleaning up any subscriptions.
  void dispose() {
    // _hostEventSubscription?.cancel();
    _connectedCallbacks.clear();
    _disconnectedCallbacks.clear();
    print('PeerNotifier: Disposed.');
  }
}

import 'dart:async';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/conn.dart'; // For Connection (or Conn) type
import 'package:dart_libp2p/core/multiaddr.dart'; // For MultiAddr type

import 'blacklist.dart'; // To potentially use the Blacklist in a SimplePeerGater

// DisconnectReason equivalent (could be an enum or const strings)
// For now, using a simple String. A more structured type might be better.
typedef DisconnectReason = String;

const DisconnectReason ReasonNoReason = ""; // Example reason

/// Interface for a PubSub PeerGater.
///
/// A PeerGater allows PubSub to implement policies for accepting or rejecting
/// connections and streams from peers, potentially based on PubSub-specific criteria
/// like blacklisting, protocol support, or peer scores (once implemented).
///
/// These checks are typically in addition to any general connection gating
/// mechanisms at the main libp2p Host level.
abstract class PeerGater {
  /// InterceptPeerDial is called before dialing a peer.
  /// Returning `false` will prevent the dial.
  FutureOr<bool> interceptPeerDial(PeerId peerId);

  /// InterceptAddrDial is called before dialing a specific address of a peer.
  /// Returning `false` will prevent dialing this specific address.
  FutureOr<bool> interceptAddrDial(PeerId peerId, MultiAddr multiaddr);

  /// InterceptAccept is called when an inbound connection is accepted.
  /// Returning `false` will close the connection.
  FutureOr<bool> interceptAccept(Conn connection);

  /// InterceptSecured is called when a connection has been secured (e.g., Noise/TLS).
  /// [isOutbound] indicates the direction of the connection.
  /// Returning `false` will close the connection.
  FutureOr<bool> interceptSecured(PeerId peerId, Conn connection, bool isOutbound);

  /// InterceptUpgraded is called after a connection has been upgraded to a muxer.
  /// Returning `false` will close the connection.
  /// [reason] can provide a specific reason for disconnection if not allowing.
  (FutureOr<bool> allow, DisconnectReason reason) interceptUpgraded(Conn connection);
}

/// A simple implementation of [PeerGater].
///
/// This implementation can be configured, for example, to use a [Blacklist].
class SimplePeerGater implements PeerGater {
  final Blacklist? blacklist; // Optional blacklist to consult

  SimplePeerGater({this.blacklist});

  @override
  FutureOr<bool> interceptPeerDial(PeerId peerId) {
    if (blacklist?.contains(peerId) ?? false) {
      print('SimplePeerGater: Denying dial to blacklisted peer ${peerId.toBase58()}');
      return false;
    }
    return true;
  }

  @override
  FutureOr<bool> interceptAddrDial(PeerId peerId, MultiAddr multiaddr) {
    // Could add address-specific rules here if needed.
    // For now, defers to interceptPeerDial logic.
    if (blacklist?.contains(peerId) ?? false) {
      print('SimplePeerGater: Denying dial to address $multiaddr for blacklisted peer ${peerId.toBase58()}');
      return false;
    }
    return true;
  }

  @override
  FutureOr<bool> interceptAccept(Conn connection) {
    final remotePeerId = connection.remotePeer; // Assuming Conn has remotePeer
    if (blacklist?.contains(remotePeerId) ?? false) {
      print('SimplePeerGater: Denying accept from blacklisted peer ${remotePeerId.toBase58()}');
      return false;
    }
    return true;
  }

  @override
  FutureOr<bool> interceptSecured(PeerId peerId, Conn connection, bool isOutbound) {
    if (blacklist?.contains(peerId) ?? false) {
      print('SimplePeerGater: Denying secured connection with blacklisted peer ${peerId.toBase58()}');
      return false;
    }
    return true;
  }

  @override
  (FutureOr<bool> allow, DisconnectReason reason) interceptUpgraded(Conn connection) {
    final remotePeerId = connection.remotePeer; // Assuming Conn has remotePeer
    if (blacklist?.contains(remotePeerId) ?? false) {
      print('SimplePeerGater: Denying upgraded connection with blacklisted peer ${remotePeerId.toBase58()}');
      return (false, "peer is blacklisted");
    }
    return (true, ReasonNoReason);
  }
}

// Note: The actual integration of this PeerGater into the dart_libp2p Host's
// connection lifecycle (e.g., via a ConnectionGater interface on the Host)
// is a separate step and depends on the Host API. PubSub would instantiate
// a PeerGater and register it with the Host if such a mechanism exists.

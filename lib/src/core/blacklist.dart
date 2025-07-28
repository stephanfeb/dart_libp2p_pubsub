import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Manages a list of blacklisted peers.
///
/// Peers can be added to the blacklist, and the blacklist can be queried
/// to check if a peer is currently blacklisted.
class Blacklist {
  final Set<PeerId> _blacklistedPeers = {};

  // TODO: Implement TTL for blacklist entries.
  // This would require storing an expiry time with each PeerId and a GC mechanism.
  // final Map<PeerId, DateTime> _blacklistedPeersWithExpiry = {};
  // Timer _gcTimer;

  /// Adds a peer to the blacklist.
  ///
  /// If the peer is already blacklisted, this operation has no effect.
  void add(PeerId peerId) {
    if (_blacklistedPeers.add(peerId)) {
      print('Blacklist: Peer ${peerId.toBase58()} added to blacklist.');
    }
  }

  /// Removes a peer from the blacklist.
  ///
  /// If the peer is not in the blacklist, this operation has no effect.
  void remove(PeerId peerId) {
    if (_blacklistedPeers.remove(peerId)) {
      print('Blacklist: Peer ${peerId.toBase58()} removed from blacklist.');
    }
  }

  /// Checks if a peer is currently in the blacklist.
  ///
  /// Returns `true` if the peer is blacklisted, `false` otherwise.
  bool contains(PeerId peerId) {
    // TODO: If TTL is implemented, check for expiry here.
    return _blacklistedPeers.contains(peerId);
  }

  /// Returns the number of peers currently in the blacklist.
  int get length => _blacklistedPeers.length;

  /// Clears all peers from the blacklist.
  void clear() {
    _blacklistedPeers.clear();
    print('Blacklist: Cleared.');
  }

  // TODO: Implement GC mechanism if using TTLs.
  // void _startGc() { ... }
  // void dispose() { _gcTimer?.cancel(); }
}

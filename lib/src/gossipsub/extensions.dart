import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../pb/rpc.pb.dart' as pb;

/// The GossipSub v1.3 extensions a node supports, as go-libp2p-pubsub's
/// `PeerExtensions`.
class PeerExtensions {
  /// The experimental test extension.
  final bool testExtension;

  const PeerExtensions({this.testExtension = false});

  /// The extensions announced in [rpc], none if it has no extensions
  /// control message.
  factory PeerExtensions.fromRpc(pb.RPC rpc) =>
      PeerExtensions(testExtension: hasExtensions(rpc) && rpc.control.extensions.testExtension);

  /// Whether [rpc] has an extensions control message.
  static bool hasExtensions(pb.RPC rpc) => rpc.hasControl() && rpc.control.hasExtensions();

  bool get isEmpty => !testExtension;

  /// [rpc] with these extensions announced in its control message. [rpc]
  /// itself is not changed.
  pb.RPC extend(pb.RPC rpc) {
    if (isEmpty) return rpc;
    final out = pb.RPC.fromBuffer(rpc.writeToBuffer());
    out.ensureControl().extensions = pb.ControlExtensions()..testExtension = testExtension;
    return out;
  }
}

/// The test extension, as go-libp2p-pubsub's `WithTestExtension`: once both
/// sides announced it, each sends the other a `TestExtension` message.
class TestExtensionConfig {
  /// Called when a peer sends us a `TestExtension` message.
  final void Function(PeerId from)? onReceiveTestExtension;

  const TestExtensionConfig({this.onReceiveTestExtension});
}

/// The extensions exchange with each peer, as go-libp2p-pubsub's
/// `extensionsState`: each side announces its extensions in its first RPC
/// and only there. Once both sides have, the extensions they share are
/// active.
class ExtensionsState {
  final PeerExtensions mine;
  final TestExtensionConfig? _testExtension;

  /// Penalises a peer that announced its extensions twice.
  final void Function(PeerId peer) _reportMisbehavior;

  final void Function(PeerId peer, pb.RPC rpc) _sendRpc;

  /// The extensions each peer announced in its first RPC.
  final Map<PeerId, PeerExtensions> _peerExtensions = {};

  /// The peers we sent our first RPC to.
  final Set<PeerId> _sent = {};

  ExtensionsState({
    TestExtensionConfig? testExtension,
    required void Function(PeerId peer) reportMisbehavior,
    required void Function(PeerId peer, pb.RPC rpc) sendRpc,
  })  : mine = PeerExtensions(testExtension: testExtension != null),
        _testExtension = testExtension,
        _reportMisbehavior = reportMisbehavior,
        _sendRpc = sendRpc;

  /// The extensions [peer] announced, if it sent its first RPC.
  PeerExtensions? of(PeerId peer) => _peerExtensions[peer];

  /// Handles an RPC from [from]: its first RPC carries its extensions; an
  /// extensions message in a later one is misbehaviour.
  void handleRpc(PeerId from, pb.RPC rpc) {
    if (!_peerExtensions.containsKey(from)) {
      _peerExtensions[from] = PeerExtensions.fromRpc(rpc);
      if (_sent.contains(from)) _addPeer(from);
    } else if (PeerExtensions.hasExtensions(rpc)) {
      _reportMisbehavior(from);
    }
    if (mine.testExtension && (_peerExtensions[from]?.testExtension ?? false) && rpc.hasTestExtension()) {
      _testExtension?.onReceiveTestExtension?.call(from);
    }
  }

  /// Our first RPC to [to], with our extensions.
  pb.RPC firstRpc(PeerId to, pb.RPC rpc) {
    final out = mine.extend(rpc);
    _sent.add(to);
    if (_peerExtensions.containsKey(to)) _addPeer(to);
    return out;
  }

  void removePeer(PeerId peer) {
    _peerExtensions.remove(peer);
    _sent.remove(peer);
  }

  /// Both sides announced their extensions: start the shared ones.
  void _addPeer(PeerId peer) {
    if (mine.testExtension && _peerExtensions[peer]!.testExtension) {
      // After the first RPC, which is being written.
      Future.microtask(() => _sendRpc(peer, pb.RPC()..testExtension = pb.TestExtension()));
    }
  }
}

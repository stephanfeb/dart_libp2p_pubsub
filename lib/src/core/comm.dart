import 'dart:async';
import 'dart:typed_data';

// Corrected imports based on PeerId's location and typical libp2p structure
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/stream.dart'; // Using P2PStream directly
import 'package:dart_libp2p/core/network/context.dart' as p2p_context; // For Host.newStream context

import '../pb/rpc.pb.dart' as pb;

// Protocol IDs
// Note: go-libp2p-pubsub uses "/meshsub/1.1.0" for GossipSub v1.1
// and "/floodsub/1.0.0" for FloodSub.
// Other versions like GossipSub v1.0 ("/meshsub/1.0.0") also exist.
// We'll primarily focus on GossipSub v1.1.0.

const String gossipSubIDv11 = '/meshsub/1.1.0';
const String floodSubID = '/floodsub/1.0.0';
// Potentially add more as needed, e.g., gossipSubIDv10 = '/meshsub/1.0.0';

/// Handles the raw communication for PubSub messages over libp2p.
///
/// This class is responsible for:
/// - Registering protocol handlers with the libp2p Host.
/// - Encoding and decoding RPC messages.
/// - Sending RPC messages to peers.
/// - Receiving RPC messages from peers and forwarding them for processing.
class PubSubProtocol {
  final Host _host;
  final Future<void> Function(PeerId peerId, pb.RPC rpc) _onRpcReceived; // PeerId type is now resolved

  /// Creates a new [PubSubProtocol] instance.
  ///
  /// [_host] is the libp2p Host.
  /// [_onRpcReceived] is a callback function that will be invoked when a new
  /// RPC message is received from a peer.
  PubSubProtocol(this._host, this._onRpcReceived) {
    _host.setStreamHandler(gossipSubIDv11, _handleNewStreamData);
    // TODO: Register for other supported protocols like floodSubID if needed.
    print('PubSubProtocol initialized and stream handler for $gossipSubIDv11 registered.');
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

  /// Sends an RPC message to a specific peer.
  ///
  /// [peerId] is the recipient peer.
  /// [rpc] is the RPC message to send.
  /// [protocolId] is the specific PubSub protocol ID to use for the new stream.
  Future<void> sendRpc(PeerId peerId, pb.RPC rpc, String protocolId) async { // PeerId type is now resolved
    print('Attempting to send RPC to $peerId on protocol $protocolId: ${rpc.toShortString()}');
    try {
      // final connection = await _host.connect(peerId); // Ensure connection
      // final stream = await connection.newStream([protocolId]);
      // TODO: Replace above with actual Host API to open a new stream.
      // This is a placeholder for how one might get a stream.
      // The actual API might be _host.newStream(peerId, [protocolId]);

      // For now, let's assume we need to get a connection first, then a stream.
      // This part is highly dependent on the dart_libp2p Host API.
      // Example:
      // final stream = await _host.dialPeer(peerId, protocolId); // Fictional API

      // Placeholder for stream opening logic
      // This needs to be replaced with the correct dart_libp2p API call
      // to open a new outbound stream to the peer for the given protocol.
      final P2PStream stream = await _host.newStream(peerId, [protocolId], p2p_context.Context());

      final bytes = rpc.writeToBuffer();
      await stream.write(bytes); // Use P2PStream.write()
      await stream.close(); // Close the stream after writing (or just the write side if possible)

      print('RPC sent to $peerId on $protocolId successfully.');
    } catch (e, s) {
      print('Error sending RPC to $peerId on $protocolId: $e');
      print(s);
      // Rethrow or handle as appropriate for the PubSub logic.
      rethrow;
    }
  }

  /// Closes the protocol handler and cleans up resources.
  Future<void> close() async {
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

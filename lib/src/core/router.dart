import 'dart:async';

import 'package:dart_libp2p/core/peer/peer_id.dart';

import 'pubsub.dart'; // For PubSub type, if router needs direct access
import 'message.dart'; // For PubSubMessage
import '../pb/rpc.pb.dart' as pb; // For pb.RPC
import 'topic.dart'; // For Topic

/// Interface for a PubSub message router.
///
/// A router is responsible for the actual logic of how messages are propagated
/// through the PubSub network, including managing connections to peers for
/// specific topics and handling protocol-specific RPCs.
abstract class Router {
  /// Attaches the router to a PubSub instance.
  /// This is where the router can initialize itself, get a reference to PubSub,
  /// and potentially register its protocol handlers via PubSub's comms layer.
  Future<void> attach(PubSub pubsub);

  /// Detaches the router from PubSub.
  /// Should clean up any resources, stop protocol handlers, etc.
  Future<void> detach();

  /// Notifies the router that a new peer has been connected and supports
  /// a PubSub protocol that this router handles.
  ///
  /// [peerId] is the ID of the peer.
  /// [protocolId] is the specific protocol ID negotiated with the peer (e.g., /meshsub/1.1.0).
  Future<void> addPeer(PeerId peerId, String protocolId);

  /// Notifies the router that a peer has been disconnected.
  Future<void> removePeer(PeerId peerId);

  /// Handles an incoming RPC message from a peer.
  ///
  /// [peerId] is the sender of the RPC.
  /// [rpc] is the decoded RPC message.
  Future<void> handleRpc(PeerId peerId, pb.RPC rpc);

  /// Publishes a message to the network.
  ///
  /// [message] is the PubSubMessage to be published.
  /// The router is responsible for finding appropriate peers and sending the message.
  Future<void> publish(PubSubMessage message);

  /// Notifies the router that the local node has joined a topic.
  /// The router may need to update its internal state, subscribe to the topic
  /// on the network (e.g., send GRAFT messages in GossipSub).
  Future<void> join(Topic topic);

  /// Notifies the router that the local node has left a topic.
  /// The router may need to update its internal state and unsubscribe from the
  /// topic on the network (e.g., send PRUNE messages in GossipSub).
  Future<void> leave(Topic topic);

  /// Starts the router's operations (e.g., heartbeats, internal timers).
  /// This is typically called after attach().
  Future<void> start();

  /// Stops the router's operations.
  /// This is typically called before detach().
  Future<void> stop();
}

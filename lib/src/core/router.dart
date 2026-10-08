import 'dart:async';

import 'package:dart_libp2p/core/peer/peer_id.dart';

import 'pubsub.dart'; // For PubSub type, if router needs direct access
import 'message.dart'; // For PubSubMessage
import '../pb/rpc.pb.dart' as pb; // For pb.RPC
import 'topic.dart'; // For Topic

/// Which RPCs of a peer to handle, as go-libp2p-pubsub's `AcceptStatus`.
enum AcceptStatus {
  /// Handle the whole RPC.
  all,

  /// Handle only the control messages and subscriptions.
  control,

  /// Ignore the RPC.
  none,
}

/// Whether [router] is ready to publish on [topic], as go-libp2p-pubsub's
/// `RouterReady`. See [PubSub.publish].
typedef RouterReady = bool Function(Router router, String topic);

/// Ready when the router has [size] peers on the topic, as
/// go-libp2p-pubsub's `MinTopicSize`: see [Router.enoughPeers]. The router
/// decides, and the local node is not counted.
RouterReady minTopicSize(int size) => (router, topic) => router.enoughPeers(topic, size);

/// Interface for a PubSub message router.
///
/// A router is responsible for the actual logic of how messages are propagated
/// through the PubSub network, including managing connections to peers for
/// specific topics and handling protocol-specific RPCs.
abstract class Router {
  /// The protocols the router speaks, in order of preference, as
  /// go-libp2p-pubsub's `Router.Protocols`. PubSub accepts streams on each
  /// and negotiates one of them with each peer.
  List<String> get protocols;

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

  /// Whether the router has enough peers on [topic], as go-libp2p-pubsub's
  /// `Router.EnoughPeers`. [suggested] is the number of peers wanted; 0
  /// means the router's own number. Discovery looks for more peers on the
  /// topics that do not have enough.
  bool enoughPeers(String topic, int suggested);

  /// Which parts of the RPCs of [peer] to handle, as go-libp2p-pubsub's
  /// `Router.AcceptFrom`. GossipSub ignores the RPCs of graylisted peers.
  AcceptStatus acceptFrom(PeerId peer);

  /// Handles an incoming RPC message from a peer.
  ///
  /// [peerId] is the sender of the RPC.
  /// [rpc] is the decoded RPC message.
  /// Returns the set of message ID strings that were accepted (not duplicates
  /// or rejected). PubSub uses this to deliver only accepted messages locally.
  ///
  /// The RPCs of a peer are handed over in order, without waiting for the
  /// previous one's future, so that a slow validation does not hold up the
  /// peer's later RPCs. A router must therefore handle the subscriptions and
  /// control messages of [rpc] synchronously, before its first `await`, to
  /// handle them in the order the peer sent them.
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc);

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

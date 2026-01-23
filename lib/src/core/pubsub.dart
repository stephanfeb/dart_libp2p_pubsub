// Imports
import 'dart:async';
import 'dart:typed_data'; // For Uint8List, ByteData, Endian

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/keys.dart'; // For PrivateKey
import '../pb/rpc.pb.dart' as pb;

import 'subscription.dart';
import 'router.dart';
import 'comm.dart';
import 'message.dart'; // For PubSubMessage used in publish
import 'sign.dart'; // For signMessage
// Ensure ValidationResult and validateFullMessage are available
import 'validation.dart';
import '../tracing/tracer.dart'; // For EventTracer
// NoOpEventTracer is in tracer.dart, so json_tracer.dart import might not be needed for default.
// import '../tracing/impl/json_tracer.dart'; 
import '../pb/trace.pb.dart' as trace_pb; // For trace event types
import '../gossipsub/score.dart'; // For PeerScore
import '../gossipsub/score_params.dart'; // For PeerScoreParams
// Ensure MessageIdFunction is available from midgen
import '../util/midgen.dart';

// TODO: Define Message class to be used in Subscription and PubSub
// import 'message.dart'; // Or from pb/rpc.pb.dart // This is redundant now

/// Type definition for a message validator function.
///
/// A validator function takes a topic string and a message (likely a `Message`
/// object once defined, using `dynamic` for now) and returns a `ValidationResult`
/// (enum or class to be defined, using `bool` as a placeholder for now,
/// where `true` means valid).
///
/// TODO: Define Message class and ValidationResult enum/class.
typedef MessageValidator = bool Function(String topic, dynamic message);

/// The main class for PubSub operations.
///
/// This class will handle subscriptions, topic management, message validation,
/// and publishing.
class PubSub {
  final Host host;
  final Router router;
  final EventTracer tracer;
  final PeerScoreParams scoreParams;
  final PrivateKey? _privateKey; // For signing outgoing messages
  late final PubSubProtocol _comms;
  late final MessageIdGenerator _idGenerator; // For generating sequence numbers

  /// Manages scores for known peers.
  final Map<PeerId, PeerScore> peerScores = {};

  PubSubProtocol get comms => _comms;

  // TODO: Consider making PubSub an async initializable class if attach needs to be awaited.
  PubSub(this.host, this.router, {PrivateKey? privateKey, EventTracer? tracer, PeerScoreParams? scoreParams}) :
    _privateKey = privateKey,
    this.tracer = tracer ?? const NoOpEventTracer(),
    this.scoreParams = scoreParams ?? PeerScoreParams.defaultParams,
    _idGenerator = MessageIdGenerator() { // Initialize the ID generator
    _comms = PubSubProtocol(host, _handleRpc);
    // It's important that the router is attached so it can also set up its
    // own protocol handlers or react to PubSub initialization.
    router.attach(this).then((_) {
      print('PubSub: Router attached successfully.');
      // Optionally, start the router after attachment if it has a start method
      // that should run post-attachment.
      // router.start();
    }).catchError((e, s) {
      print('PubSub: Error attaching router: $e\n$s');
      // Handle router attachment failure, e.g., PubSub might not be usable.
    });
  }

  Future<void> _handleRpc(PeerId peerId, pb.RPC rpc) async {
    // Let the router process the RPC first.
    // The router is responsible for validation, mcache, forwarding, and handling control messages.
    await router.handleRpc(peerId, rpc);

    // After router processing, if the RPC contained publish messages that the
    // router deemed valid (implicitly, by not rejecting them and potentially putting them in mcache),
    // then PubSub should deliver them to its local subscribers.
    if (rpc.publish.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        // The router should have validated the message.
        // We construct a PubSubMessage for local delivery.
        final pubSubMessage = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);

        // We need to ensure this message was indeed accepted by the router.
        // A robust way would be for router.handleRpc to return information about accepted messages.
        // Lacking that, a common pattern is to check if the message is now in the router's cache,
        // but the cache (_mcache) is private to GossipSubRouter.
        // Another heuristic: if the message is for a topic we are subscribed to.
        // The router's handleRpc for GossipSub already traces DELIVER_MESSAGE if it accepts it.
        // PubSub's role here is purely local delivery to its subscribers.

        // Let's assume that if router.handleRpc completed without error for this message,
        // and it's a publish message, it's intended for potential local delivery
        // if there are subscribers.
        deliverReceivedMessage(pubSubMessage);
      }
    }
  }

  /// Stores subscriptions, mapping topic strings to a list of [Subscription] objects.
  final Map<String, List<Subscription>> _subscriptions = {};

  /// Provides the function used to generate message IDs, as expected by routers.
  MessageIdFn get messageIdFn => defaultMessageIdFn;

  /// Subscribes to a given topic.
  ///
  /// Returns a [Subscription] object that can be used to receive messages
  /// and to unsubscribe.
  Subscription subscribe(String topic) {
    _subscriptions.putIfAbsent(topic, () => []);

    late Subscription subscription; // Declare subscription here to use in the callback

    // Define the cancel callback for the subscription.
    // This callback removes the specific subscription from the list.
    Future<void> cancelSubscriptionCallback() async {
      final topicSubscriptions = _subscriptions[topic];
      if (topicSubscriptions != null) {
        topicSubscriptions.remove(subscription);
        if (topicSubscriptions.isEmpty) {
          _subscriptions.remove(topic);
        }
      }
      // Additional cleanup if needed (e.g., notify router)
    }

    subscription = Subscription(topic, cancelSubscriptionCallback);
    _subscriptions[topic]!.add(subscription);

    print('Subscribed to topic: $topic. Subscription created.');
    return subscription;
  }

  /// Unsubscribes all listeners from a given topic.
  ///
  /// This will cancel all [Subscription] objects associated with the topic.
  /// Individual subscriptions can also be cancelled using their `cancel()` method.
  Future<void> unsubscribe(String topic) async {
    if (_subscriptions.containsKey(topic)) {
      final topicSubscriptions = List<Subscription>.from(_subscriptions[topic]!); // Create a copy to iterate
      for (final sub in topicSubscriptions) {
        await sub.cancel(); // This will also remove it from _subscriptions via its callback
      }
      // The list in _subscriptions should be empty now and potentially the key removed
      // if all subscriptions were cancelled and removed themselves.
      // We can add an explicit remove if the list might not be empty due to callback issues (though it shouldn't).
      if (_subscriptions[topic]?.isEmpty ?? false) {
         _subscriptions.remove(topic);
      }
      print('All subscriptions for topic "$topic" cancelled and removed.');
    } else {
      print('Not subscribed to topic: $topic, nothing to unsubscribe.');
    }
  }

  /// Returns a list of topics the client is currently subscribed to.
  List<String> getTopics() {
    return _subscriptions.keys.toList();
  }

  // --- Message Validation ---

  final List<MessageValidator> _validators = [];

  /// Registers a message validator.
  ///
  /// Validators are called in order of registration. If any validator
  /// marks a message as invalid, subsequent validators are not called.
  void registerMessageValidator(MessageValidator validator) {
    _validators.add(validator);
  }

  /// Internal method to validate a message.
  ///
  /// TODO: Implement fully. This will iterate through _validators.
  /// For now, it's a placeholder.
  // TODO: Update _validateMessage to use PubSubMessage and return ValidationResult
  // This method might be better placed in validation.dart or called from there.
  // For now, keeping the old signature but acknowledging it needs update.
  // bool _validateMessage(String topic, dynamic data) { ... old implementation ... }

  /// Validates an incoming message using the registered validators and built-in checks.
  /// This is expected to be called by the Router.
  Future<ValidationResult> validateMessage(PubSubMessage message) async {
    // TODO: Integrate custom _validators if their signature is updated to PubSubMessage -> ValidationResult
    // For now, relies on validateFullMessage which includes structural and signature checks.
    return await validateFullMessage(message);
  }

  // --- Message Publishing ---

  /// Publishes data to a given topic.
  ///
  /// The data is validated, wrapped in a PubSubMessage, and then passed to the
  /// router for propagation.
  Future<void> publish(String topic, Uint8List data) async {
    // Construct the pb.Message first
    // 'from' should be the local peer's ID.
    // 'seqno' should be generated (e.g., timestamp based or counter).
    // This requires access to local PeerId and a sequence number generator.
    // These are not yet part of PubSub class. Adding TODOs.
    // TODO: Get local PeerId (e.g., from this.host.id.toBytes())
    // TODO: Implement sequence number generation (e.g., MidSN from go-libp2p-pubsub) - Done via MessageIdGenerator
    
    final localPeerIdBytes = host.id.toBytes(); // Assuming host.id returns PeerId, and PeerId has toBytes()
    final seqno = _idGenerator.nextSeqno(); // Use MessageIdGenerator

    final pbMsg = pb.Message()
      ..from = localPeerIdBytes
      ..data = data
      ..seqno = seqno
      ..topic = topic;

    // Sign the message if privateKey is available
    if (_privateKey != null) {
      await signMessage(pbMsg, _privateKey!);
    }

    final pubSubMessage = PubSubMessage(
      rpcMessage: pbMsg,
      receivedFrom: null, // Locally published, so receivedFrom is null
    );

    // Validate the constructed PubSubMessage
    if (await validateMessage(pubSubMessage) != ValidationResult.accept) {
      print('PubSub: Constructed message for topic "$topic" is invalid. Dropping.');
      // Optionally, trace a REJECT_MESSAGE or similar event here if desired for local drops
      return;
    }

    // Trace the publish event
    final String msgIdStr = defaultMessageIdFn(pbMsg); // Use from midgen.dart
    final List<int> msgIdBytes = msgIdStr.codeUnits; // UTF-8 bytes of the string ID

    final publishMsgTrace = trace_pb.TraceEvent_PublishMessage()
      ..messageID = msgIdBytes
      ..topic = topic;
    
    final traceEvent = trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.PUBLISH_MESSAGE // Ensure this enum constant is correct
      ..publishMessage = publishMsgTrace;
    tracer.trace(traceEvent);
    
    // Delegate to the router for actual publishing logic
    await router.publish(pubSubMessage);

    // Deliver to local subscribers as well
    // This part remains similar, but now uses the constructed PubSubMessage or its data.
    if (_subscriptions.containsKey(topic)) {
      final topicSubscriptions = _subscriptions[topic]!;
      if (topicSubscriptions.isNotEmpty) {
        print('PubSub: Delivering local message to ${topicSubscriptions.length} subscribers on topic "$topic".');
        for (final sub in List<Subscription>.from(topicSubscriptions)) {
          // Subscription.deliver expects 'dynamic'. We can pass PubSubMessage or just its data.
          // For consistency with network messages, PubSubMessage might be better.
          sub.deliver(pubSubMessage);
        }
      }
    }
  }

  // TODO: Add start() and stop() methods to PubSub to manage lifecycle of router and comms.
  Future<void> start() async {
    print('PubSub: Starting...');
    await tracer.start();
    await router.start();
    // _comms is started implicitly by its constructor (registers handlers).
    print('PubSub: Started successfully.');
  }

  Future<void> stop() async {
    print('PubSub: Stopping...');
    await router.stop();
    await _comms.close(); // Unregisters protocol handlers
    await tracer.stop();
    await tracer.dispose();
    print('PubSub: Stopped successfully.');
  }

  /// Delivers a message to local subscribers.
  /// This can be called by the router for messages received from the network,
  /// or internally for locally published messages if direct local delivery is bypassed in publish().
  void deliverMessage(PubSubMessage message) {
    // This method is what GossipSubRouter expects to call.
    // It can delegate to deliverReceivedMessage or have its own logic.
    // For now, let's make it an alias or the primary path.
    deliverReceivedMessage(message);
  }

  /// Delivers a message received from the network to local subscribers.
  /// This is typically called by the active Router after it has processed
  /// and validated an incoming message.
  void deliverReceivedMessage(PubSubMessage message) {
    final topic = message.topic; // Assuming PubSubMessage has a 'topic' getter for the primary topic
    if (_subscriptions.containsKey(topic)) {
      final topicSubscriptions = _subscriptions[topic]!;
      if (topicSubscriptions.isNotEmpty) {
        print('PubSub: Delivering network message on topic "$topic" from ${message.receivedFrom?.toBase58() ?? "unknown"} to ${topicSubscriptions.length} local subscribers.');
        for (final sub in List<Subscription>.from(topicSubscriptions)) {
          // Subscription.deliver expects 'dynamic'. We pass the PubSubMessage.
          sub.deliver(message);
        }
      }
    }
  }

  // --- Peer Score Management ---

  /// Called by the router when a peer connects and supports the pubsub protocol.
  void addPeer(PeerId peerId, String protocolId) {
    // Router also calls its own addPeer. This is for PubSub's internal management if needed,
    // like initializing scores.
    if (!peerScores.containsKey(peerId)) {
      peerScores[peerId] = PeerScore(peerId, scoreParams);
      print('PubSub: Initialized score for new peer ${peerId.toBase58()}');
    }
  }

  /// Called by the router when a peer disconnects.
  void removePeer(PeerId peerId) {
    // Router also calls its own removePeer. This is for PubSub's internal cleanup.
    peerScores.remove(peerId);
    
    // Close the persistent stream to this peer
    _comms.closePeerStream(peerId).catchError((e) {
      print('PubSub: Error closing stream to ${peerId.toBase58()}: $e');
    });
    
    print('PubSub: Removed score for disconnected peer ${peerId.toBase58()}');
  }

  /// Retrieves the current score for a given peer.
  /// If the peer is unknown, creates a new score entry with neutral initial score.
  /// For GossipSub, it's important that peers have a score entry.
  double? getPeerScore(PeerId peerId) {
    final peerScoreInstance = peerScores.putIfAbsent(peerId, () {
      print('PubSub: Peer ${peerId.toBase58()} not found in scores, creating new entry with neutral score.');
      return PeerScore(peerId, scoreParams);
    });
    return peerScoreInstance.score;
  }

  /// Allows the router (or other components) to access the PeerScore object directly
  /// to record specific scoring events.
  PeerScore? getPeerScoreObject(PeerId peerId) {
     return peerScores.putIfAbsent(peerId, () {
      print('PubSub: Peer ${peerId.toBase58()} not found in scores, creating new entry for object access.');
      return PeerScore(peerId, scoreParams);
    });
  }

  /// Periodically called (e.g., by GossipSubRouter's heartbeat) to refresh scores.
  void refreshScores() {
    for (final peerScore in peerScores.values) {
      peerScore.refreshScore();
    }
  }
}

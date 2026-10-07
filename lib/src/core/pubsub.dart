// Imports
import 'dart:async';
import 'dart:typed_data'; // For Uint8List, ByteData, Endian

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/notifiee.dart';
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
import 'package:logging/logging.dart';

export 'validation.dart' show ValidationResult;

final _log = Logger('PubSub');

// TODO: Define Message class to be used in Subscription and PubSub
// import 'message.dart'; // Or from pb/rpc.pb.dart // This is redundant now

/// A legacy, synchronous message validator that applies to every topic.
///
/// It takes the topic string and the received message (a [PubSubMessage]).
/// It returns `true` to accept the message and `false` to reject it. A
/// rejected message is not forwarded or delivered, and the peer that sent it
/// is penalised. Register it with [PubSub.registerMessageValidator].
///
/// Prefer [TopicValidator] for new code: it can be async and it can return
/// [ValidationResult.ignore].
typedef MessageValidator = bool Function(String topic, dynamic message);

/// A validator for the messages of one topic, as in go-libp2p-pubsub's
/// `RegisterTopicValidator`.
///
/// [receivedFrom] is the peer that delivered the message to us (the local
/// host's ID for a message we publish). The original author is
/// `message.from`.
///
/// The validator returns (or completes with):
/// - [ValidationResult.accept]: the message is forwarded and delivered.
/// - [ValidationResult.reject]: the message is dropped and the delivering
///   peer is penalised. Use this only for messages that are invalid.
/// - [ValidationResult.ignore]: the message is dropped without a penalty.
///   Use this for messages that are valid but not wanted (for example,
///   stale or not relevant to this node).
///
/// A validator that throws is treated as [ValidationResult.ignore].
typedef TopicValidator = FutureOr<ValidationResult> Function(
    PeerId receivedFrom, PubSubMessage message);

/// The default time limit for one run of a [TopicValidator]. A validator that
/// does not complete in time gives [ValidationResult.ignore].
const Duration defaultValidatorTimeout = Duration(seconds: 5);

/// The default maximum number of messages that can be in validation at the
/// same time, over all topics (as `defaultValidateThrottle` in
/// go-libp2p-pubsub). More messages are dropped as
/// [ValidationResult.ignore].
const int defaultValidateThrottle = 8192;

/// The default maximum number of concurrent runs of one topic's
/// [TopicValidator] (as `defaultValidateConcurrency` in go-libp2p-pubsub).
const int defaultValidatorConcurrency = 1024;

/// Trace reasons for dropped messages, as in go-libp2p-pubsub.
const String _rejectInvalidStructure = 'invalid message';
const String _rejectInvalidSignature = 'invalid signature';
const String _rejectValidationFailed = 'validation failed';
const String _rejectValidationIgnored = 'validation ignored';
const String _rejectValidationThrottled = 'validation throttled';
const String _rejectValidationTimeout = 'validation timeout';

class _TopicValidatorEntry {
  final TopicValidator validator;
  final Duration timeout;
  final int concurrency;
  int active = 0;

  _TopicValidatorEntry(this.validator, this.timeout, this.concurrency);
}

/// The main class for PubSub operations.
///
/// This class will handle subscriptions, topic management, message validation,
/// and publishing.
class PubSub {
  final Host host;
  final Router router;
  final EventTracer tracer;
  final PeerScoreParams scoreParams;

  /// The default time limit for one run of a [TopicValidator].
  /// [Duration.zero] means no limit.
  final Duration validatorTimeout;

  /// The maximum number of messages in validation at the same time, over
  /// all topics.
  final int validateThrottle;

  final PrivateKey? _privateKey; // For signing outgoing messages
  late final PubSubProtocol _comms;

  /// Sends our subscriptions to each peer that connects, and tells the router
  /// when a peer disconnects. Registered with the host's network while the
  /// PubSub is started.
  Notifiee? _networkNotifiee;
  late final MessageIdGenerator _idGenerator; // For generating sequence numbers

  /// Manages scores for known peers.
  final Map<PeerId, PeerScore> peerScores = {};

  PubSubProtocol get comms => _comms;

  /// Creates a PubSub service on [host] that routes messages with [router].
  ///
  /// Published messages are signed with [privateKey], or with the host's own
  /// private key from its peerstore when [privateKey] is omitted. A message's
  /// `from` is always the host's peer ID, so [privateKey] must be the host's
  /// key; peers reject a signature from any other key.
  ///
  /// [validatorTimeout] is the default time limit for one run of a
  /// [TopicValidator] (see [registerTopicValidator]); [Duration.zero] means
  /// no limit. [validateThrottle] is the maximum number of messages in
  /// validation at the same time, over all topics; when it is reached, new
  /// messages are dropped as [ValidationResult.ignore].
  // TODO: Consider making PubSub an async initializable class if attach needs to be awaited.
  PubSub(this.host, this.router, {
    PrivateKey? privateKey,
    EventTracer? tracer,
    PeerScoreParams? scoreParams,
    this.validatorTimeout = defaultValidatorTimeout,
    this.validateThrottle = defaultValidateThrottle,
  }) :
    _privateKey = privateKey,
    this.tracer = tracer ?? const NoOpEventTracer(),
    this.scoreParams = scoreParams ?? PeerScoreParams.defaultParams,
    _idGenerator = MessageIdGenerator() { // Initialize the ID generator
    _comms = PubSubProtocol(host, _handleRpc);
    _comms.onNewInboundPeer = (peerId) {
      // When a new GossipSub peer connects, send our subscriptions
      announceSubscriptionsTo(peerId);
    };
    // It's important that the router is attached so it can also set up its
    // own protocol handlers or react to PubSub initialization.
    router.attach(this).then((_) {
      _log.fine('PubSub: Router attached successfully.');
      // Optionally, start the router after attachment if it has a start method
      // that should run post-attachment.
      // router.start();
    }).catchError((e, s) {
      _log.warning('PubSub: Error attaching router: $e\n$s');
      // Handle router attachment failure, e.g., PubSub might not be usable.
    });
  }

  Future<void> _handleRpc(PeerId peerId, pb.RPC rpc) async {
    // Let the router process the RPC first.
    // The router is responsible for validation, mcache, forwarding, and handling control messages.
    // It returns the set of message IDs that were accepted (not duplicates or rejected).
    final acceptedIds = await router.handleRpc(peerId, rpc);

    // Only deliver messages that the router actually accepted.
    if (rpc.publish.isNotEmpty && acceptedIds.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        final msgIdStr = messageIdFn(msgProto);
        if (!acceptedIds.contains(msgIdStr)) continue;

        final pubSubMessage = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
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

    // Announce subscription to all connected GossipSub peers
    _announceSubscription(topic, true);

    _log.fine('Subscribed to topic: $topic. Subscription created.');
    return subscription;
  }

  /// Sends a SUB/UNSUB RPC to all connected peers.
  void _announceSubscription(String topic, bool subscribe) {
    final subOpt = pb.RPC_SubOpts()
      ..subscribe = subscribe
      ..topicid = topic;
    final rpc = pb.RPC()..subscriptions.add(subOpt);

    final peers = host.network.peers;
    for (final peerId in peers) {
      _comms.sendRpc(peerId, rpc, gossipSubIDv11).catchError((e) {
        _log.fine('PubSub: Error announcing subscription to ${peerId.toBase58()}: $e');
      });
    }
  }

  /// Sends all current subscriptions to a specific peer.
  /// Called when a new GossipSub peer connects.
  void announceSubscriptionsTo(PeerId peerId) {
    if (_subscriptions.isEmpty) return;
    final rpc = pb.RPC();
    for (final topic in _subscriptions.keys) {
      rpc.subscriptions.add(pb.RPC_SubOpts()
        ..subscribe = true
        ..topicid = topic);
    }
    _comms.sendRpc(peerId, rpc, gossipSubIDv11).catchError((e) {
      _log.fine('PubSub: Error sending subscriptions to ${peerId.toBase58()}: $e');
    });
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
      _log.fine('All subscriptions for topic "$topic" cancelled and removed.');
    } else {
      _log.fine('Not subscribed to topic: $topic, nothing to unsubscribe.');
    }
  }

  /// Returns a list of topics the client is currently subscribed to.
  List<String> getTopics() {
    return _subscriptions.keys.toList();
  }

  // --- Message Validation ---

  final List<MessageValidator> _validators = [];
  final Map<String, _TopicValidatorEntry> _topicValidators = {};
  int _activeValidations = 0;

  /// Registers a legacy validator that applies to every topic.
  ///
  /// Validators are called in order of registration, after the built-in
  /// structure and signature checks and before the topic's
  /// [TopicValidator]. If any validator returns `false`, the message is
  /// rejected: it is not forwarded or delivered, the peer that sent it is
  /// penalised, and subsequent validators are not called.
  void registerMessageValidator(MessageValidator validator) {
    _validators.add(validator);
  }

  /// Registers [validator] for the messages on [topic], as
  /// `RegisterTopicValidator` in go-libp2p-pubsub.
  ///
  /// The validator runs for every new message on [topic], both received and
  /// published locally. Messages are forwarded to other peers and delivered
  /// to subscribers only when it accepts them. Duplicates of a message that
  /// was already seen are dropped before validation, so the validator runs
  /// once per message.
  ///
  /// [timeout] limits one run of the validator (default: the PubSub's
  /// [validatorTimeout]; [Duration.zero] means no limit). A run that takes
  /// longer gives [ValidationResult.ignore]. [concurrency] limits how many
  /// runs of this validator can be active at the same time (default
  /// [defaultValidatorConcurrency]); more messages are dropped as
  /// [ValidationResult.ignore].
  ///
  /// Only one validator can be registered for a topic. Throws a [StateError]
  /// if [topic] already has one; call [unregisterTopicValidator] first.
  void registerTopicValidator(
    String topic,
    TopicValidator validator, {
    Duration? timeout,
    int? concurrency,
  }) {
    if (_topicValidators.containsKey(topic)) {
      throw StateError('PubSub: a validator is already registered for topic "$topic"');
    }
    final effectiveConcurrency = concurrency ?? defaultValidatorConcurrency;
    if (effectiveConcurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be at least 1');
    }
    _topicValidators[topic] = _TopicValidatorEntry(
        validator, timeout ?? validatorTimeout, effectiveConcurrency);
  }

  /// Removes the validator of [topic], as `UnregisterTopicValidator` in
  /// go-libp2p-pubsub. Returns `false` if [topic] had no validator.
  bool unregisterTopicValidator(String topic) {
    return _topicValidators.remove(topic) != null;
  }

  /// Validates a message. The router calls this for each new message it
  /// receives, and [publish] calls it for each local message.
  ///
  /// The checks run in this order: the global throttle
  /// ([validateThrottle]), message structure and size, the signature, the
  /// validators of [registerMessageValidator], and the topic's
  /// [TopicValidator]. The first result that is not
  /// [ValidationResult.accept] is returned. A dropped message that was
  /// received from a peer is traced as REJECT_MESSAGE with the reason.
  Future<ValidationResult> validateMessage(PubSubMessage message) async {
    if (_activeValidations >= validateThrottle) {
      _log.fine('PubSub: validation throttled ($validateThrottle active); dropping message on "${message.topic}".');
      _traceReject(message, _rejectValidationThrottled);
      return ValidationResult.ignore;
    }
    _activeValidations++;
    try {
      final (result, reason) = await _runValidation(message);
      if (result != ValidationResult.accept) {
        _traceReject(message, reason!);
      }
      return result;
    } finally {
      _activeValidations--;
    }
  }

  Future<(ValidationResult, String?)> _runValidation(PubSubMessage message) async {
    if (validateMessageStructure(message) != ValidationResult.accept) {
      return (ValidationResult.reject, _rejectInvalidStructure);
    }
    ValidationResult signatureResult;
    try {
      signatureResult = await validateMessageSignature(message);
    } catch (e) {
      // For example, a 'from' field that is not a valid peer ID.
      _log.fine('PubSub: signature check failed with an error: $e');
      signatureResult = ValidationResult.reject;
    }
    if (signatureResult != ValidationResult.accept) {
      return (ValidationResult.reject, _rejectInvalidSignature);
    }

    final topic = message.topic;
    for (final validator in List<MessageValidator>.from(_validators)) {
      try {
        if (!validator(topic, message)) {
          return (ValidationResult.reject, _rejectValidationFailed);
        }
      } catch (e, s) {
        _log.warning('PubSub: message validator threw on topic "$topic": $e\n$s');
        return (ValidationResult.ignore, _rejectValidationIgnored);
      }
    }

    final entry = _topicValidators[topic];
    if (entry == null) {
      return (ValidationResult.accept, null);
    }
    if (entry.active >= entry.concurrency) {
      _log.fine('PubSub: validator for "$topic" throttled (${entry.concurrency} active); dropping message.');
      return (ValidationResult.ignore, _rejectValidationThrottled);
    }
    entry.active++;
    try {
      var timedOut = false;
      var future = Future<ValidationResult>.sync(
          () => entry.validator(message.receivedFrom ?? host.id, message));
      if (entry.timeout > Duration.zero) {
        future = future.timeout(entry.timeout, onTimeout: () {
          timedOut = true;
          return ValidationResult.ignore;
        });
      }
      final result = await future;
      if (timedOut) {
        _log.fine('PubSub: validator for "$topic" timed out after ${entry.timeout}; ignoring message.');
        return (ValidationResult.ignore, _rejectValidationTimeout);
      }
      switch (result) {
        case ValidationResult.accept:
          return (ValidationResult.accept, null);
        case ValidationResult.reject:
          return (ValidationResult.reject, _rejectValidationFailed);
        case ValidationResult.ignore:
          return (ValidationResult.ignore, _rejectValidationIgnored);
      }
    } catch (e, s) {
      _log.warning('PubSub: validator for topic "$topic" threw: $e\n$s');
      return (ValidationResult.ignore, _rejectValidationIgnored);
    } finally {
      entry.active--;
    }
  }

  void _traceReject(PubSubMessage message, String reason) {
    final from = message.receivedFrom;
    if (from == null) return; // Local publish: publish() logs the drop.
    final rejectTrace = trace_pb.TraceEvent_RejectMessage()
      ..messageID = messageIdFn(message.rpcMessage).codeUnits
      ..receivedFrom = from.toBytes()
      ..topic = message.topic
      ..reason = reason;
    tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.REJECT_MESSAGE
      ..peerID = from.toBytes()
      ..rejectMessage = rejectTrace);
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

    // Validation requires a signature (strict signing), so sign every message.
    // Without an explicit privateKey, use the host's own key from its
    // peerstore, as go-libp2p-pubsub does.
    final signingKey = _privateKey ?? await host.peerStore.keyBook.privKey(host.id);
    if (signingKey == null) {
      throw StateError(
          'PubSub: cannot sign messages: no privateKey was given and the '
          'peerstore holds no private key for ${host.id.toBase58()}');
    }
    await signMessage(pbMsg, signingKey);

    final pubSubMessage = PubSubMessage(
      rpcMessage: pbMsg,
      receivedFrom: null, // Locally published, so receivedFrom is null
    );

    // Validate the constructed PubSubMessage, with the same validators as
    // received messages.
    final validation = await validateMessage(pubSubMessage);
    if (validation != ValidationResult.accept) {
      _log.warning('PubSub: Message for topic "$topic" failed local validation ($validation). Dropping.');
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
        _log.fine('PubSub: Delivering local message to ${topicSubscriptions.length} subscribers on topic "$topic".');
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
    _log.fine('PubSub: Starting...');
    await tracer.start();
    await router.start();
    if (_networkNotifiee == null) {
      final notifiee = NotifyBundle(connectedF: (network, conn, {Duration? dialLatency}) {
        // As in go-libp2p-pubsub, each side sends its subscriptions to a new
        // peer, so that both know which topics they share.
        announceSubscriptionsTo(conn.remotePeer);
      }, disconnectedF: (network, conn) {
        final peerId = conn.remotePeer;
        // A peer can have several connections: it is gone when the last one closes.
        if (network.connsToPeer(peerId).isNotEmpty) return;
        router.removePeer(peerId).catchError((e, s) {
          _log.warning('PubSub: Error removing disconnected peer ${peerId.toBase58()}: $e\n$s');
        });
      });
      host.network.notify(notifiee);
      _networkNotifiee = notifiee;
    }
    // _comms is started implicitly by its constructor (registers handlers).
    _log.fine('PubSub: Started successfully.');
  }

  Future<void> stop() async {
    _log.fine('PubSub: Stopping...');
    final notifiee = _networkNotifiee;
    if (notifiee != null) {
      host.network.stopNotify(notifiee);
      _networkNotifiee = null;
    }
    await router.stop();
    await _comms.close(); // Unregisters protocol handlers
    await tracer.stop();
    await tracer.dispose();
    _log.fine('PubSub: Stopped successfully.');
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
        _log.fine('PubSub: Delivering network message on topic "$topic" from ${message.receivedFrom?.toBase58() ?? "unknown"} to ${topicSubscriptions.length} local subscribers.');
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
      _log.fine('PubSub: Initialized score for new peer ${peerId.toBase58()}');
    }
  }

  /// Called by the router when a peer disconnects.
  ///
  /// The peer's score is kept, so a peer cannot clear its penalties by
  /// reconnecting.
  void removePeer(PeerId peerId) {
    // Router also calls its own removePeer. This is for PubSub's internal cleanup.
    // Close the persistent stream to this peer
    _comms.closePeerStream(peerId).catchError((e) {
      _log.fine('PubSub: Error closing stream to ${peerId.toBase58()}: $e');
    });
    
    _log.fine('PubSub: Removed disconnected peer ${peerId.toBase58()}');
  }

  /// Retrieves the current score for a given peer.
  /// If the peer is unknown, creates a new score entry with neutral initial score.
  /// For GossipSub, it's important that peers have a score entry.
  double? getPeerScore(PeerId peerId) {
    final peerScoreInstance = peerScores.putIfAbsent(peerId, () {
      _log.fine('PubSub: Peer ${peerId.toBase58()} not found in scores, creating new entry with neutral score.');
      return PeerScore(peerId, scoreParams);
    });
    return peerScoreInstance.score;
  }

  /// Allows the router (or other components) to access the PeerScore object directly
  /// to record specific scoring events.
  PeerScore? getPeerScoreObject(PeerId peerId) {
     return peerScores.putIfAbsent(peerId, () {
      _log.fine('PubSub: Peer ${peerId.toBase58()} not found in scores, creating new entry for object access.');
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

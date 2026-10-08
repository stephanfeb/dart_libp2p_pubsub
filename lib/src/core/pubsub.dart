// Imports
import 'dart:async';
import 'dart:math';
import 'dart:typed_data'; // For Uint8List, ByteData, Endian

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/keys.dart'; // For PrivateKey
import 'package:dart_libp2p/core/discovery.dart';
import 'package:fixnum/fixnum.dart';
import '../pb/rpc.pb.dart' as pb;

import 'subscription.dart';
import 'router.dart';
import 'notify.dart';
import 'blacklist.dart';
import 'discovery.dart';
import 'topic.dart';
import 'comm.dart';
import 'message.dart'; // For PubSubMessage used in publish
import 'sign.dart'; // For signMessage
// Ensure ValidationResult and validateFullMessage are available
import 'validation.dart';
import '../tracing/tracer.dart'; // For EventTracer
// NoOpEventTracer is in tracer.dart, so json_tracer.dart import might not be needed for default.
// import '../tracing/impl/json_tracer.dart'; 
import '../pb/trace.pb.dart' as trace_pb; // For trace event types
// Ensure MessageIdFunction is available from midgen
import '../util/midgen.dart';
import 'package:logging/logging.dart';

export 'validation.dart' show ValidationResult;
export 'sign.dart' show MessageSignaturePolicy;

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
const String _rejectMissingSignature = 'missing signature';
const String _rejectUnexpectedSignature = 'unexpected signature';
const String _rejectUnexpectedAuthInfo = 'unexpected auth info';
const String _rejectSelfOrigin = 'self originated message';
const String _rejectBlacklistedPeer = 'blacklisted peer';
const String _rejectBlacklistedSource = 'blacklisted source';
const String _rejectValidationFailed = 'validation failed';
const String _rejectValidationIgnored = 'validation ignored';
const String _rejectValidationThrottled = 'validation throttled';
const String _rejectValidationTimeout = 'validation timeout';
/// Not a reject reason: the message was marked seen by another copy first.
const String _duplicate = 'duplicate';

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

  /// The default time limit for one run of a [TopicValidator].
  /// [Duration.zero] means no limit.
  final Duration validatorTimeout;

  /// The maximum number of messages in validation at the same time, over
  /// all topics.
  final int validateThrottle;

  /// The maximum size of one RPC on the wire, in bytes.
  final int maxMessageSize;

  final MessageIdFn _messageIdFn;

  /// How messages are signed and verified.
  final MessageSignaturePolicy signaturePolicy;

  /// Whether our messages omit `from` and `seqno`.
  final bool noAuthor;

  /// The peers whose RPCs and messages are dropped, as go-libp2p-pubsub's
  /// `WithBlacklist`. Add peers with [blacklistPeer], which also drops a
  /// peer already connected.
  final Blacklist blacklist;

  final PrivateKey? _privateKey; // For signing outgoing messages

  /// Advertises and searches for the peers of our topics, when a
  /// [Discovery] was given.
  final PubSubDiscovery? _discovery;
  late final PubSubProtocol _comms;

  /// Sends our subscriptions to each peer that connects, and tells the router
  /// when a peer disconnects. Set while the PubSub is started.
  PeerNotifier? _peerNotifier;
  late final MessageIdGenerator _idGenerator; // For generating sequence numbers

  /// The connected peers that speak pubsub: those that opened a pubsub
  /// stream to us or accepted ours. They are added to the router.
  final Set<PeerId> _peers = {};

  /// The peers we are sending the hello packet to. Subscription changes are
  /// sent to them too, as go-libp2p-pubsub queues RPCs for a new peer before
  /// its stream is open: the hello may have been built before the change.
  final Set<PeerId> _greeting = {};

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
  ///
  /// [maxMessageSize] is the maximum size of one RPC on the wire, in bytes,
  /// as go-libp2p-pubsub's `WithMaxMessageSize` (default 1 MiB). All nodes
  /// of a network should use the same value.
  ///
  /// [signaturePolicy] is go-libp2p-pubsub's `WithMessageSignaturePolicy`
  /// (default [MessageSignaturePolicy.strictSign]). [noAuthor] omits `from`
  /// and `seqno` from our messages and turns off signing, as
  /// `WithNoAuthor`; use it with a content-based [messageIdFn].
  ///
  /// [messageIdFn] computes message IDs, as go-libp2p-pubsub's
  /// `WithMessageIdFn` (default [defaultMessageIdFn], which is Go's
  /// `DefaultMsgIdFn`). All nodes of a network must use the same function.
  ///
  /// [discovery] finds peers for our topics, as go-libp2p-pubsub's
  /// `WithDiscovery`: each subscribed topic is advertised under the
  /// namespace `floodsub:<topic>`, and while the router has not enough
  /// peers on a subscribed topic (see [Router.enoughPeers]) PubSub searches
  /// for its peers and dials them, with the connector [discoveryConnector]
  /// creates (default [defaultDiscoveryConnector]). [discoveryOptions] are
  /// passed to each call of [discovery], as `WithDiscoveryOpts`.
  // TODO: Consider making PubSub an async initializable class if attach needs to be awaited.
  PubSub(this.host, this.router, {
    PrivateKey? privateKey,
    EventTracer? tracer,
    this.validatorTimeout = defaultValidatorTimeout,
    this.validateThrottle = defaultValidateThrottle,
    this.maxMessageSize = defaultMaxMessageSize,
    MessageIdFn messageIdFn = defaultMessageIdFn,
    MessageSignaturePolicy signaturePolicy = MessageSignaturePolicy.strictSign,
    this.noAuthor = false,
    Blacklist? blacklist,
    Discovery? discovery,
    List<DiscoveryOption> discoveryOptions = const [],
    DiscoveryConnectorFactory? discoveryConnector,
  }) :
    blacklist = blacklist ?? Blacklist(),
    signaturePolicy = noAuthor && signaturePolicy.mustSign
        ? (signaturePolicy.mustVerify ? MessageSignaturePolicy.strictNoSign : MessageSignaturePolicy.laxNoSign)
        : signaturePolicy,
    _messageIdFn = messageIdFn,
    _privateKey = privateKey,
    _discovery = discovery == null
        ? null
        : PubSubDiscovery(discovery, options: discoveryOptions, connector: discoveryConnector),
    this.tracer = tracer ?? const NoOpEventTracer(),
    _idGenerator = MessageIdGenerator() { // Initialize the ID generator
    _comms = PubSubProtocol(host, _handleRpc, maxMessageSize: maxMessageSize, protocols: router.protocols);
    _comms.onNewInboundPeer = _handleInboundPeer;
    _comms.onPeerDead = _handlePeerDead;
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
    if (blacklist.contains(peerId)) {
      _log.fine('PubSub: Ignoring RPC from blacklisted peer ${peerId.toBase58()}.');
      return;
    }
    // As go-libp2p-pubsub: the router decides whether to handle the RPCs of
    // the peer at all (GossipSub ignores graylisted peers).
    switch (router.acceptFrom(peerId)) {
      case AcceptStatus.none:
        _log.fine('PubSub: Ignoring RPC from ${peerId.toBase58()}, refused by the router.');
        return;
      case AcceptStatus.control:
        rpc = pb.RPC()
          ..subscriptions.addAll(rpc.subscriptions)
          ..control = rpc.control;
      case AcceptStatus.all:
        // As go-libp2p-pubsub: messages for topics we do not subscribe to
        // are ignored, before validation.
        if (rpc.publish.any((m) => !_subscriptions.containsKey(m.topic))) {
          final filtered = pb.RPC()
            ..subscriptions.addAll(rpc.subscriptions)
            ..publish.addAll(rpc.publish.where((m) => _subscriptions.containsKey(m.topic)));
          if (rpc.hasControl()) filtered.control = rpc.control;
          _log.fine('PubSub: Ignoring ${rpc.publish.length - filtered.publish.length} messages from '
              '${peerId.toBase58()} for topics we do not subscribe to.');
          rpc = filtered;
        }
    }
    // Let the router process the RPC first.
    // The router is responsible for validation, mcache, forwarding, and handling control messages.
    // It returns the set of message IDs that were accepted (not duplicates or rejected).
    final acceptedIds = await router.handleRpc(peerId, rpc);

    // Only deliver messages that the router actually accepted, once each.
    if (rpc.publish.isNotEmpty && acceptedIds.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        final msgIdStr = messageIdFn(msgProto);
        if (!acceptedIds.remove(msgIdStr)) continue;

        final pubSubMessage = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
        deliverReceivedMessage(pubSubMessage);
      }
    }
  }

  /// Stores subscriptions, mapping topic strings to a list of [Subscription] objects.
  final Map<String, List<Subscription>> _subscriptions = {};

  /// The function that computes message IDs. Its IDs are byte strings (see
  /// [MessageIdFn]).
  MessageIdFn get messageIdFn => _normalizedMessageId;

  String _normalizedMessageId(pb.Message message) => normalizeMessageId(_messageIdFn(message));

  /// Subscribes to a given topic.
  ///
  /// Returns a [Subscription] object that can be used to receive messages
  /// and to unsubscribe.
  Subscription subscribe(String topic) {
    final firstSubscription = _subscriptions[topic]?.isNotEmpty != true;
    _subscriptions.putIfAbsent(topic, () => []);

    late Subscription subscription; // Declare subscription here to use in the callback

    // Define the cancel callback for the subscription.
    // This callback removes the specific subscription from the list.
    Future<void> cancelSubscriptionCallback() async {
      final topicSubscriptions = _subscriptions[topic];
      if (topicSubscriptions != null) {
        topicSubscriptions.remove(subscription);
        if (topicSubscriptions.isEmpty) {
          // As in go-libp2p-pubsub: the last subscription to a topic
          // announces the unsubscription and leaves the topic's mesh.
          _subscriptions.remove(topic);
          _discovery?.stopAdvertise(topic);
          _announceSubscription(topic, false);
          await router.leave(Topic(topic));
        }
      }
    }

    subscription = Subscription(topic, cancelSubscriptionCallback);
    _subscriptions[topic]!.add(subscription);

    // As go-libp2p-pubsub: look for peers of the topic, and advertise it on
    // the first subscription.
    _discovery?.discover(topic);
    if (firstSubscription) _discovery?.advertise(topic);

    // Announce subscription to all connected GossipSub peers
    _announceSubscription(topic, true);

    // As in go-libp2p-pubsub: the first subscription to a topic joins the
    // topic's mesh.
    if (firstSubscription) {
      router.join(Topic(topic)).catchError((e, s) {
        _log.warning('PubSub: Error joining topic $topic: $e\n$s');
      });
    }

    _log.fine('Subscribed to topic: $topic. Subscription created.');
    return subscription;
  }

  /// Sends a SUB/UNSUB RPC to the pubsub peers.
  void _announceSubscription(String topic, bool subscribe) {
    final subOpt = pb.RPC_SubOpts()
      ..subscribe = subscribe
      ..topicid = topic;
    final rpc = pb.RPC()..subscriptions.add(subOpt);

    for (final peerId in {..._peers, ..._greeting}) {
      _comms.sendRpc(peerId, rpc, router.protocols.first).catchError((e) {
        _log.fine('PubSub: Error announcing subscription to ${peerId.toBase58()}: $e');
      });
    }
  }

  /// Sends the hello packet (all our subscriptions, possibly none) to
  /// [peerId], as go-libp2p-pubsub does to each new peer. If the peer
  /// accepts the pubsub stream, it is added to the router.
  void announceSubscriptionsTo(PeerId peerId) {
    if (blacklist.contains(peerId)) return;
    final rpc = pb.RPC();
    for (final topic in _subscriptions.keys) {
      rpc.subscriptions.add(pb.RPC_SubOpts()
        ..subscribe = true
        ..topicid = topic);
    }
    _greeting.add(peerId);
    _comms.sendRpc(peerId, rpc, router.protocols.first).then((_) {
      _addPeer(peerId, _comms.protocolOf(peerId) ?? router.protocols.first);
    }).catchError((e) {
      // Typically a peer that does not speak pubsub.
      _log.fine('PubSub: Could not open a pubsub stream to ${peerId.toBase58()}: $e');
    }).whenComplete(() => _greeting.remove(peerId));
  }

  /// A peer opened a pubsub stream to us: it speaks pubsub.
  void _handleInboundPeer(PeerId peerId, String protocol) {
    final isNew = !_peers.contains(peerId);
    _addPeer(peerId, protocol);
    // Make sure it has our subscriptions, if we have not greeted it yet.
    if (isNew) announceSubscriptionsTo(peerId);
  }

  /// The backoff of greeting again peers that ended our stream to them.
  final _deadPeerBackoff = _DeadPeerBackoff();

  /// A peer ended our stream to it, as go-libp2p-pubsub's handleDeadPeers:
  /// it is removed from the router and, if still connected (it restarted
  /// its pubsub, or a duplicate connection closed), greeted again after a
  /// backoff, which opens a new stream and adds it back.
  void _handlePeerDead(PeerId peerId) {
    if (!_peers.contains(peerId)) return;
    _log.fine('PubSub: Peer ${peerId.toBase58()} ended our stream to it.');
    router.removePeer(peerId).catchError((e) {
      _log.warning('PubSub: Error removing peer ${peerId.toBase58()}: $e');
    });
    _peers.remove(peerId);
    if (!host.network.peers.contains(peerId)) return;
    final delay = _deadPeerBackoff.next(peerId);
    if (delay == null) {
      _log.fine('PubSub: Giving up on ${peerId.toBase58()} after too many dead streams.');
      return;
    }
    Timer(delay, () {
      if (!_stopped && !_peers.contains(peerId) && host.network.peers.contains(peerId)) {
        announceSubscriptionsTo(peerId);
      }
    });
  }

  /// Blacklists [peerId], as go-libp2p-pubsub's `BlacklistPeer`: its RPCs
  /// and the messages it forwards or wrote are dropped from now on, and if
  /// it is a pubsub peer, it is removed from the router and its stream
  /// closed.
  void blacklistPeer(PeerId peerId) {
    _log.fine('PubSub: Blacklisting peer ${peerId.toBase58()}.');
    blacklist.add(peerId);
    if (_peers.contains(peerId)) {
      router.removePeer(peerId).catchError((e) {
        _log.warning('PubSub: Error removing peer ${peerId.toBase58()}: $e');
      });
      _peers.remove(peerId);
    }
  }

  void _addPeer(PeerId peerId, String protocol) {
    if (_stopped) return; // A greeting that completed after stop().
    if (blacklist.contains(peerId)) return; // As go-libp2p-pubsub.
    if (!host.network.peers.contains(peerId)) return; // Gone already.
    if (_peers.add(peerId)) {
      router.addPeer(peerId, protocol).catchError((e) {
        _log.warning('PubSub: Error adding peer ${peerId.toBase58()} to the router: $e');
      });
    }
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
  ///
  /// [markSeen], if given, is called once the signature has been verified,
  /// before the validators run, as in go-libp2p-pubsub: it marks the
  /// message's ID as seen and returns `false` if it was seen already, in
  /// which case validation stops with [ValidationResult.ignore] and nothing
  /// is traced (the caller handles the duplicate). Marking a message seen
  /// only after its signature is verified keeps a forged copy from blocking
  /// the genuine message. A router can tell a message that failed the
  /// structure or signature checks by [markSeen] not having been called.
  ///
  /// [onReject], if given, is called with the reason of a dropped message,
  /// one of go-libp2p-pubsub's rejection reasons (such as `validation
  /// throttled`), as Go's raw tracers get it.
  Future<ValidationResult> validateMessage(PubSubMessage message,
      {bool Function()? markSeen, void Function(String reason)? onReject}) async {
    if (_activeValidations >= validateThrottle) {
      _log.fine('PubSub: validation throttled ($validateThrottle active); dropping message on "${message.topic}".');
      _traceReject(message, _rejectValidationThrottled);
      onReject?.call(_rejectValidationThrottled);
      return ValidationResult.ignore;
    }
    _activeValidations++;
    try {
      final (result, reason) = await _runValidation(message, markSeen);
      if (reason == _duplicate) return result;
      if (result != ValidationResult.accept) {
        _traceReject(message, reason!);
        onReject?.call(reason);
      }
      return result;
    } finally {
      _activeValidations--;
    }
  }

  bool _isBlacklistedAuthor(List<int> from) {
    if (from.isEmpty || blacklist.length == 0) return false;
    try {
      return blacklist.contains(PeerId.fromBytes(Uint8List.fromList(from)));
    } catch (_) {
      return false; // Not a peer ID; the signing policy checks reject it.
    }
  }

  /// The checks of go-libp2p-pubsub's `checkSigningPolicy` and its
  /// self-origin check, for a received message: the reject reason, or null.
  String? _checkSigningPolicy(PubSubMessage message) {
    final msg = message.rpcMessage;
    final received = message.receivedFrom != null;
    if (!received) return null;
    if (msg.from.isNotEmpty && _sameBytes(msg.from, host.id.toBytes())) {
      return _rejectSelfOrigin;
    }
    if (!signaturePolicy.mustVerify) return null;
    if (signaturePolicy.mustSign) {
      if (msg.signature.isEmpty) return _rejectMissingSignature;
    } else {
      if (msg.signature.isNotEmpty) return _rejectUnexpectedSignature;
      // Not authoring messages: no author data is expected either.
      if (noAuthor && (msg.seqno.isNotEmpty || msg.from.isNotEmpty || msg.key.isNotEmpty)) {
        return _rejectUnexpectedAuthInfo;
      }
    }
    return null;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<(ValidationResult, String?)> _runValidation(PubSubMessage message, bool Function()? markSeen) async {
    // As go-libp2p-pubsub's shouldPush: messages forwarded by a blacklisted
    // peer, or written by one, are dropped before anything else.
    final source = message.receivedFrom;
    if (source != null && blacklist.contains(source)) {
      return (ValidationResult.ignore, _rejectBlacklistedPeer);
    }
    if (_isBlacklistedAuthor(message.rpcMessage.from)) {
      return (ValidationResult.ignore, _rejectBlacklistedSource);
    }
    final policyViolation = _checkSigningPolicy(message);
    if (policyViolation != null) return (ValidationResult.reject, policyViolation);
    if (validateMessageStructure(message,
            maxMessageSize: maxMessageSize, requireAuthor: signaturePolicy == MessageSignaturePolicy.strictSign) !=
        ValidationResult.accept) {
      return (ValidationResult.reject, _rejectInvalidStructure);
    }
    // As go-libp2p-pubsub: a signature, if present, is verified (its
    // presence is required by the policy check above).
    if (message.rpcMessage.signature.isNotEmpty) {
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
    }
    if (markSeen != null && !markSeen()) {
      return (ValidationResult.ignore, _duplicate);
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

  /// Whether a tracer is set. Callers can skip building trace events when
  /// it is not.
  bool get tracing => tracer is! NoOpEventTracer;

  /// Sends [event] to the [tracer], stamped as go-libp2p-pubsub stamps every
  /// trace event: with the local peer ID and the time, in nanoseconds since
  /// the Unix epoch.
  void traceEvent(trace_pb.TraceEvent event) {
    if (!tracing) return;
    tracer.trace(event
      ..peerID = host.id.toBytes()
      ..timestamp = Int64(DateTime.now().microsecondsSinceEpoch) * 1000);
  }

  void _traceReject(PubSubMessage message, String reason) {
    final from = message.receivedFrom;
    if (from == null) return; // Local publish: publish() logs the drop.
    final rejectTrace = trace_pb.TraceEvent_RejectMessage()
      ..messageID = messageIdToBytes(messageIdFn(message.rpcMessage))
      ..receivedFrom = from.toBytes()
      ..topic = message.topic
      ..reason = reason;
    traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.REJECT_MESSAGE
      ..rejectMessage = rejectTrace);
  }

  // --- Message Publishing ---

  /// Publishes data to a given topic.
  ///
  /// The data is validated, wrapped in a PubSubMessage, and then passed to the
  /// router for propagation.
  ///
  /// With [ready], waits first until the router is ready to publish on
  /// [topic], as go-libp2p-pubsub's `WithReadiness`; for example
  /// `ready: minTopicSize(3)`. While it waits, PubSub searches for peers of
  /// the topic if it has a [Discovery]. If [readyTimeout] passes first, the
  /// message is not published and a [TimeoutException] is thrown; if
  /// PubSub stops first, a [StateError].
  Future<void> publish(String topic, Uint8List data, {RouterReady? ready, Duration? readyTimeout}) async {
    if (ready != null) await _waitUntilReady(topic, ready, readyTimeout);

    // Construct the pb.Message first
    // 'from' should be the local peer's ID.
    // 'seqno' should be generated (e.g., timestamp based or counter).
    // This requires access to local PeerId and a sequence number generator.
    // These are not yet part of PubSub class. Adding TODOs.
    // TODO: Get local PeerId (e.g., from this.host.id.toBytes())
    // TODO: Implement sequence number generation (e.g., MidSN from go-libp2p-pubsub) - Done via MessageIdGenerator
    
    // As go-libp2p-pubsub's Topic.Publish: the author and a sequence
    // number, unless noAuthor, and a signature if the policy signs.
    final pbMsg = pb.Message()
      ..data = data
      ..topic = topic;
    if (!noAuthor) {
      pbMsg
        ..from = host.id.toBytes()
        ..seqno = _idGenerator.nextSeqno();
    }
    if (signaturePolicy.mustSign) {
      // Without an explicit privateKey, use the host's own key from its
      // peerstore, as go-libp2p-pubsub does.
      final signingKey = _privateKey ?? await host.peerStore.keyBook.privKey(host.id);
      if (signingKey == null) {
        throw StateError(
            'PubSub: cannot sign messages: no privateKey was given and the '
            'peerstore holds no private key for ${host.id.toBase58()}');
      }
      await signMessage(pbMsg, signingKey);
    }

    // The message must fit in one RPC, or no peer would accept it.
    final rpcSize = (pb.RPC()..publish.add(pbMsg)).writeToBuffer().length;
    if (rpcSize > maxMessageSize) {
      throw ArgumentError.value(data.length, 'data',
          'message of $rpcSize bytes exceeds the maximum message size of $maxMessageSize bytes');
    }

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
    final List<int> msgIdBytes = messageIdToBytes(messageIdFn(pbMsg));

    final publishMsgTrace = trace_pb.TraceEvent_PublishMessage()
      ..messageID = msgIdBytes
      ..topic = topic;
    
    traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.PUBLISH_MESSAGE
      ..publishMessage = publishMsgTrace);
    
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

  /// Waits until [ready] holds for [topic], as go-libp2p-pubsub's
  /// `Publish` with `WithReadiness`: checks every 100 ms and, with
  /// discovery, searches for peers of the topic between checks.
  Future<void> _waitUntilReady(String topic, RouterReady ready, Duration? timeout) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (!ready(router, topic)) {
      if (_stopped) throw StateError('PubSub stopped before topic $topic was ready');
      var wait = const Duration(milliseconds: 100);
      if (deadline != null) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) {
          throw TimeoutException('Topic $topic was not ready to publish', timeout);
        }
        final search = _discovery?.discover(topic);
        if (search != null) await search.timeout(left, onTimeout: () {});
        if (left < wait) wait = left;
      } else {
        await _discovery?.discover(topic);
      }
      await Future.delayed(wait);
    }
  }

  /// Whether [stop] was called after the last [start].
  bool _stopped = false;

  /// Starts the router and greets the connected peers. After [stop], starts
  /// again: the protocol handlers are registered again, the subscribed
  /// topics joined again and the connected peers greeted again.
  Future<void> start() async {
    _log.fine('PubSub: Starting...');
    if (_stopped) {
      _stopped = false;
      _comms.start();
    }
    await tracer.start();
    await router.start();
    // Topics subscribed to before a stop are joined again (joining a topic
    // already joined does nothing).
    for (final topic in _subscriptions.keys) {
      router.join(Topic(topic)).catchError((e, s) {
        _log.warning('PubSub: Error joining topic $topic: $e\n$s');
      });
    }
    final discovery = _discovery;
    if (discovery != null) {
      discovery.start(host, router, () => _subscriptions.keys.toList());
      for (final topic in _subscriptions.keys) {
        discovery.advertise(topic);
      }
    }
    if (_peerNotifier == null) {
      _peerNotifier = PeerNotifier(host)
        // As in go-libp2p-pubsub, each side sends its subscriptions to a new
        // peer, so that both know which topics they share.
        ..onPeerConnected((peerId) {
          if (!_peers.contains(peerId)) announceSubscriptionsTo(peerId);
        })
        ..onPeerDisconnected(router.removePeer);
      // Greet the peers connected before start, as go-libp2p-pubsub does.
      for (final peerId in host.network.peers) {
        if (!_peers.contains(peerId)) announceSubscriptionsTo(peerId);
      }
    }
    _log.fine('PubSub: Started successfully.');
  }

  /// Stops the router, removes all peers from it and closes all pubsub
  /// streams, so that the node no longer takes part in the network.
  ///
  /// Subscriptions and validators are kept: after [start], the node joins
  /// its topics again and the subscriptions receive messages again. To end
  /// a subscription's stream, cancel it. The tracer is flushed but not
  /// disposed; dispose it after the last stop.
  Future<void> stop() async {
    _log.fine('PubSub: Stopping...');
    _stopped = true;
    _discovery?.stop();
    _peerNotifier?.dispose();
    _peerNotifier = null;
    for (final peerId in _peers.toList()) {
      await router.removePeer(peerId);
    }
    _peers.clear();
    _greeting.clear();
    await router.stop();
    await _comms.close(); // Unregisters protocol handlers, closes streams.
    await tracer.stop();
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

  /// Called by the router when a peer disconnects: closes the stream to it.
  void removePeer(PeerId peerId) {
    _peers.remove(peerId);
    _comms.closePeerStream(peerId).catchError((e) {
      _log.fine('PubSub: Error closing stream to ${peerId.toBase58()}: $e');
    });
    _log.fine('PubSub: Removed disconnected peer ${peerId.toBase58()}');
  }
}

/// The backoff of go-libp2p-pubsub's `backoff`, for greeting again a peer
/// that ended our stream to it: none the first time, then 100 ms doubling
/// (with up to 100 ms of jitter) to 10 s, and at most 4 attempts within
/// 10 minutes.
final _random = Random();

class _DeadPeerBackoff {
  static const _min = Duration(milliseconds: 100);
  static const _max = Duration(seconds: 10);
  static const _timeToLive = Duration(minutes: 10);
  static const _maxAttempts = 4;

  final Map<PeerId, ({Duration delay, DateTime lastTried, int attempts})> _history = {};

  /// The delay before the next attempt for [peerId], or null if it had too
  /// many.
  Duration? next(PeerId peerId) {
    final now = DateTime.now();
    _history.removeWhere((_, h) => now.difference(h.lastTried) > _timeToLive);
    final h = _history[peerId];
    Duration delay;
    if (h == null) {
      delay = Duration.zero;
    } else if (h.attempts >= _maxAttempts) {
      return null;
    } else if (h.delay < _min) {
      delay = _min;
    } else if (h.delay < _max) {
      delay = h.delay * 2 + Duration(milliseconds: _random.nextInt(100));
      if (delay > _max) delay = _max;
    } else {
      delay = h.delay;
    }
    _history[peerId] = (delay: delay, lastTried: now, attempts: (h?.attempts ?? 0) + 1);
    return delay;
  }
}


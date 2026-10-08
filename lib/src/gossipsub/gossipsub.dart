import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'dart:collection';

import 'package:dart_libp2p/core/certified_addr_book.dart';
import 'package:dart_libp2p/core/network/common.dart' show Direction;
import 'package:dart_libp2p/core/network/network.dart' show Connectedness;
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/peer/record.dart';
import 'package:dart_libp2p/core/peerstore.dart' show AddressTTL;
import 'package:dart_libp2p/core/record/envelope.dart';
import 'package:clock/clock.dart';
import 'package:fixnum/fixnum.dart';

import '../core/pubsub.dart';
import '../core/message.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/topic.dart';
import '../core/router.dart';
import '../core/comm.dart'; // For RpcShortString and gossipSubIDv11
import 'rpc_queue.dart';
import 'mcache.dart';
import 'score.dart';
import 'score_params.dart';
import 'peer_gater.dart';
import 'extensions.dart';
import '../pb/trace.pb.dart' as trace_pb;
import '../util/midgen.dart';
import '../util/timecache.dart';
import 'package:logging/logging.dart';

final _log = Logger('GossipSubRouter');

final _random = Random();

/// The parameters of GossipSub, as go-libp2p-pubsub's `GossipSubParams`.
/// The defaults are Go's.
class GossipSubParams {
  /// The target number of peers in the mesh of a topic.
  final int D;

  /// The heartbeat GRAFTs peers when a mesh has fewer than this.
  final int DLow;

  /// The heartbeat PRUNEs peers when a mesh has this many or more.
  final int DHigh;

  /// When pruning an oversized mesh, the number of peers kept for their
  /// score; the others are kept at random. Must be <= DHigh.
  final int DScore;

  /// The number of outbound peers (connections we dialed) to keep in each
  /// mesh, which protects it against Sybils that connect to us. Must be
  /// < DLow and < D/2.
  final int DOut;

  /// Time to live of the fanout of a topic we published to without joining.
  final Duration fanoutTTL;

  /// The number of peers gossiped to (IHAVE) per topic at each heartbeat.
  final int DLazy;

  /// The number of peers included in the Peer Exchange of a PRUNE, and the
  /// most peers we connect to from one received PRUNE.
  final int prunePeers;

  /// The number of connections to Peer Exchange peers attempted at once
  /// (go-libp2p-pubsub's `Connectors`).
  final int connectors;

  /// The most Peer Exchange peers waiting to be connected to; more are
  /// ignored (go-libp2p-pubsub's `MaxPendingConnections`).
  final int maxPendingConnections;

  /// How long a connection attempt to a Peer Exchange peer may take
  /// (go-libp2p-pubsub's `ConnectionTimeout`).
  final Duration connectionTimeout;

  /// How long the router remembers the ID of a message it has seen
  /// (go-libp2p-pubsub's `TimeCacheDuration`).
  final Duration seenMessagesTTL;

  /// Whether [seenMessagesTTL] runs from when a message was first or last
  /// seen (go-libp2p-pubsub's `WithSeenMessagesStrategy`; default first).
  final SeenMessagesStrategy seenMessagesStrategy;

  /// Time between heartbeats.
  final Duration heartbeatInterval;

  /// Time from [GossipSubRouter.start] to the first heartbeat.
  final Duration heartbeatInitialDelay;

  /// Opportunistic grafting runs once every this many heartbeats.
  final int opportunisticGraftTicks;

  /// The number of peers GRAFTed by one opportunistic grafting.
  final int opportunisticGraftPeers;

  /// Backoff of the PRUNEs sent when leaving a topic.
  final Duration unsubscribeBackoff;

  /// Backoff of the other PRUNEs, and of a received PRUNE without one.
  final Duration pruneBackoff;

  /// A peer that GRAFTs during a backoff is penalised; twice if it does so
  /// within this time of the PRUNE.
  final Duration graftFloodThreshold;

  /// How many times a peer can request the same message with IWANT.
  final int gossipRetransmission;

  /// The longest backoff accepted from a PRUNE; longer ones are capped.
  final Duration maxPruneBackoff;

  /// Whether a message published by this node is sent to every peer of the
  /// topic with a score of at least the publish threshold, not only to the
  /// mesh (go-libp2p-pubsub's `WithFloodPublish`, default true).
  final bool floodPublish;

  /// The number of heartbeats a message stays in the message cache.
  final int historyLength;

  /// The number of recent heartbeats whose messages are gossiped (IHAVE).
  final int historyGossip;

  /// Gossip goes to this fraction of the eligible peers of a topic, at
  /// least [DLazy].
  final double gossipFactor;

  /// The maximum number of message IDs in an IHAVE we send, and the maximum
  /// number of messages we request from one peer per heartbeat.
  final int maxIHaveLength;

  /// The maximum number of IHAVEs we accept from one peer per heartbeat.
  final int maxIHaveMessages;

  /// A peer that advertised a message (IHAVE) we then requested (IWANT) must
  /// deliver it within this time, or it is penalised (broken promise).
  final Duration iwantFollowupTime;

  /// The maximum number of message IDs we accept in one IDONTWANT.
  final int maxIDontWantLength;

  /// The maximum number of IDONTWANTs we accept from a peer per heartbeat.
  final int maxIDontWantMessages;

  /// We send IDONTWANT for received messages with at least this many bytes
  /// of data.
  final int idontwantMessageThreshold;

  /// The number of heartbeats an IDONTWANT is remembered.
  final int idontwantMessageTTL;

  GossipSubParams({
    this.D = 6,
    this.DLow = 5,
    this.DHigh = 12,
    this.DScore = 4,
    this.DOut = 2,
    this.fanoutTTL = const Duration(minutes: 1),
    this.DLazy = 6,
    this.prunePeers = 16,
    this.connectors = 8,
    this.maxPendingConnections = 128,
    this.connectionTimeout = const Duration(seconds: 30),
    this.seenMessagesTTL = const Duration(minutes: 2),
    this.seenMessagesStrategy = SeenMessagesStrategy.firstSeen,
    this.heartbeatInterval = const Duration(seconds: 1),
    this.heartbeatInitialDelay = const Duration(milliseconds: 100),
    this.opportunisticGraftTicks = 60,
    this.opportunisticGraftPeers = 2,
    this.unsubscribeBackoff = const Duration(seconds: 10),
    this.pruneBackoff = const Duration(minutes: 1),
    this.graftFloodThreshold = const Duration(seconds: 10),
    this.gossipRetransmission = 3,
    this.maxPruneBackoff = const Duration(hours: 24),
    this.floodPublish = true,
    this.historyLength = 5,
    this.historyGossip = 3,
    this.gossipFactor = 0.25,
    this.maxIHaveLength = 5000,
    this.maxIHaveMessages = 10,
    this.iwantFollowupTime = const Duration(seconds: 3),
    this.maxIDontWantLength = 10,
    this.maxIDontWantMessages = 1000,
    this.idontwantMessageThreshold = 1024,
    this.idontwantMessageTTL = 3,
  }) : assert(opportunisticGraftTicks > 0);

  static GossipSubParams get defaultParams => GossipSubParams();

  /// Throws an [ArgumentError] if the parameters are not consistent, as
  /// go-libp2p-pubsub's `GossipSubParams.validate`.
  void validate() {
    if (historyGossip > historyLength) {
      throw ArgumentError('historyGossip must be <= historyLength');
    }
    if (DScore > DHigh) throw ArgumentError('DScore must be <= DHigh');
    // Bootstrappers set D = DLow = DHigh = DOut = 0 (no mesh).
    if (D == 0 && DLow == 0 && DHigh == 0 && DOut == 0) return;
    if (!(DLow <= D && D <= DHigh)) {
      throw ArgumentError('the parameters must satisfy DLow <= D <= DHigh');
    }
    if (!(DOut < DLow && DOut < D ~/ 2)) {
      throw ArgumentError('DOut must be < DLow and < D/2');
    }
  }
}

/// Implementation of the GossipSub v1.1 routing protocol, following
/// go-libp2p-pubsub's `GossipSubRouter`.
///
/// Peer scoring is enabled by giving [scoreParams] together with
/// [scoreThresholds], as go-libp2p-pubsub's `WithPeerScore(params,
/// thresholds)`; without them, every peer has a score of 0.
///
/// [doPX] turns on Peer Exchange in the PRUNEs we send (go-libp2p-pubsub's
/// `WithPeerExchange`, off by default; meant for bootstrappers and other
/// well-connected nodes).
class GossipSubRouter implements Router {
  PubSub? _pubsub;
  late final GossipSubParams params;

  /// The score thresholds; all 0 when scoring is disabled.
  final PeerScoreThresholds thresholds;

  /// Whether our PRUNEs carry Peer Exchange.
  final bool doPX;

  /// The peer scoring, or null when scoring is disabled.
  PeerScore? get score => _score;
  PeerScore? _score;

  /// Sets the score parameters of [topic] while the router runs, as
  /// go-libp2p-pubsub's `Topic.SetScoreParams`: for a topic created after
  /// the router, or to change its parameters. See
  /// [PeerScore.setTopicScoreParams]. Throws a [StateError] if scoring is
  /// disabled, and an [ArgumentError] if [params] is invalid.
  void setTopicScoreParams(String topic, TopicScoreParams params) {
    final score = _score;
    if (score == null) throw StateError('peer scoring is not enabled in the router');
    score.setTopicScoreParams(topic, params);
  }

  /// The parameters of the peer gater, as go-libp2p-pubsub's
  /// `WithPeerGater`; null (the default) turns the gater off. When
  /// validation is being throttled, the gater handles only the control
  /// messages of some peers, the more often the fewer of their messages
  /// were delivered.
  final PeerGaterParams? peerGaterParams;

  /// The peer gater, when [peerGaterParams] is given and the router is
  /// attached.
  PeerGater? get gate => _gate;
  PeerGater? _gate;

  /// The GossipSub v1.3 extensions exchanged with each peer.
  late final ExtensionsState extensions = ExtensionsState(
    testExtension: testExtension,
    // As go-libp2p-pubsub: announcing extensions twice is penalised.
    reportMisbehavior: (peer) => _score?.addPenalty(peer, 10),
    sendRpc: (peer, rpc) => _sendRpc(peer, rpc),
  );

  /// Turns on the experimental test extension of GossipSub v1.3, as
  /// go-libp2p-pubsub's `WithTestExtension`; off by default.
  final TestExtensionConfig? testExtension;

  RpcOutgoingQueueManager? _rpcQueueManagerOrNull;
  late final MessageCache _mcache;

  /// IDs of the messages seen recently. A message is marked here once its
  /// signature is verified, so its later copies are not validated again.
  late final TimeCache<String> _seenMessages;

  /// The mesh of each joined topic. A topic is joined while it has an entry.
  final Map<String, Set<PeerId>> mesh = {};

  /// The peers we publish to for topics we publish to without joining.
  final Map<String, Set<PeerId>> fanout = {};

  /// When we last published to each fanout topic.
  final Map<String, DateTime> fanoutLastPublished = {};

  /// The topics each peer is subscribed to.
  final Map<PeerId, Set<String>> _peerTopics = {};

  /// The pubsub protocol of each peer added with [addPeer].
  final Map<PeerId, String> _peerProtocols = {};

  /// Whether we dialed the connection to each peer (for DOut).
  final Map<PeerId, bool> _outbound = {};

  Timer? _heartbeatTimer;

  /// Number of heartbeats since [start].
  int _heartbeatTicks = 0;

  /// The end of the backoff of each peer, per topic: the peer must not be
  /// GRAFTed (and must not GRAFT us) before. Entries are kept until two
  /// heartbeats after they end, so that a GRAFT does not land at the very
  /// end of the remote peer's backoff.
  final Map<String, Map<PeerId, DateTime>> _backoff = {};

  /// IHAVEs received from each peer since the last heartbeat.
  final Map<PeerId, int> _peerHave = {};

  /// Messages requested (IWANT) from each peer since the last heartbeat.
  final Map<PeerId, int> _iAsked = {};

  /// IWANT promises, as go-libp2p-pubsub's `gossipTracer`: for each message
  /// we requested, the peers that must deliver it, and when.
  final Map<String, Map<PeerId, DateTime>> _promises = {};

  /// IHAVEs to send to each peer with its next RPC or the heartbeat.
  final Map<PeerId, List<pb.ControlIHave>> _gossip = {};

  /// GRAFTs and PRUNEs that could not be queued, to retry with the next RPC
  /// to the peer.
  final Map<PeerId, pb.ControlMessage> _control = {};

  /// The message IDs each peer told us it does not want (IDONTWANT), with
  /// the heartbeats left to remember them.
  final Map<PeerId, Map<String, int>> _unwanted = {};

  /// IDONTWANTs received from each peer since the last heartbeat.
  final Map<PeerId, int> _peerDontWant = {};

  /// Peer Exchange peers waiting to be connected to, with their signed peer
  /// records, as go-libp2p-pubsub's `connect` channel.
  final Queue<(PeerId, List<int>?)> _pxPending = Queue();

  /// The connections to Peer Exchange peers being attempted.
  int _pxConnecting = 0;

  /// The signed peer record of each peer, marshalled, as offered in our
  /// Peer Exchange. Fetched from the certified address book in the
  /// background, as building a PRUNE is synchronous.
  final Map<PeerId, List<int>> _signedRecords = {};

  /// The protocols of GossipSub, in order of preference, as
  /// go-libp2p-pubsub's `GossipSubDefaultProtocols` (without v1.3).
  static const List<String> defaultProtocols = [gossipSubIDv13, gossipSubIDv12, gossipSubIDv11, gossipSubIDv10, floodSubID];

  @override
  List<String> get protocols => defaultProtocols;

  /// The protocol of [peer]; a peer we have not added (it sent us an RPC
  /// before its stream was set up) is taken to speak v1.1.
  String _protocolOf(PeerId peer) => _peerProtocols[peer] ?? gossipSubIDv11;

  /// Whether [peer] has a mesh (GossipSub, not FloodSub).
  bool _supportsMesh(PeerId peer) => _protocolOf(peer).startsWith('/meshsub/');

  /// Whether [peer] takes Peer Exchange and backoff in PRUNEs (v1.1+).
  bool _supportsPX(PeerId peer) {
    final protocol = _protocolOf(peer);
    return protocol == gossipSubIDv11 || protocol == gossipSubIDv12 || protocol == gossipSubIDv13;
  }

  /// Whether [peer] speaks IDONTWANT (v1.2).
  bool _supportsIDontWant(PeerId peer) {
    final protocol = _protocolOf(peer);
    return protocol == gossipSubIDv12 || protocol == gossipSubIDv13;
  }

  /// Returns true if the router has been started and the heartbeat is active.
  bool get isStarted => _heartbeatTimer != null;

  GossipSubRouter({
    GossipSubParams? params,
    PeerScoreParams? scoreParams,
    PeerScoreThresholds? scoreThresholds,
    this.doPX = false,
    this.peerGaterParams,
    this.testExtension,
  })  : thresholds = scoreThresholds ?? const PeerScoreThresholds() {
    if ((scoreParams == null) != (scoreThresholds == null)) {
      throw ArgumentError('scoreParams and scoreThresholds must be given together');
    }
    this.params = params ?? GossipSubParams.defaultParams;
    this.params.validate();
    thresholds.validate();
    if (scoreParams != null) _score = PeerScore(scoreParams, connectionIps: _connectionIps);
    _mcache = MessageCache(historyLength: this.params.historyLength, historyGossip: this.params.historyGossip);
    _seenMessages = TimeCache<String>(this.params.seenMessagesTTL, strategy: this.params.seenMessagesStrategy);
  }

  bool _isSeen(String msgId) => _seenMessages.contains(msgId) || _mcache.seen(msgId);

  /// The ID of [message], with the PubSub's message ID function.
  String _idOf(pb.Message message) => (_pubsub?.messageIdFn ?? defaultMessageIdFn)(message);

  /// The score of [peer]: 0 when scoring is disabled.
  double _scoreOf(PeerId peer) => _score?.score(peer) ?? 0;

  @override
  Future<void> attach(PubSub pubsub) async {
    _pubsub = pubsub;
    _rpcQueueManagerOrNull = RpcOutgoingQueueManager(pubsub.comms, gossipSubIDv11,
        maxQueueSize: pubsub.peerOutboundQueueSize);
    // As go-libp2p-pubsub, a v1.3 peer gets our extensions in our first RPC.
    pubsub.comms.onFirstRpc = (peer, protocol, rpc) =>
        protocol == gossipSubIDv13 ? extensions.firstRpc(peer, rpc) : rpc;
    final gaterParams = peerGaterParams;
    if (gaterParams != null) _gate = PeerGater(gaterParams, pubsub.host);
    _log.fine('GossipSubRouter attached to PubSub and RpcQueueManager initialized.');
  }

  List<String> _connectionIps(PeerId peer) {
    final host = _pubsub?.host;
    if (host == null) return const [];
    return [
      for (final conn in host.network.connsToPeer(peer))
        if (!conn.stat.stats.limited)
          if (conn.remoteMultiaddr.ip case final ip?) ip,
    ];
  }

  @override
  Future<void> detach() async {
    await stop();
    _rpcQueueManagerOrNull?.clearAll();
    _pubsub = null;
    _log.fine('GossipSubRouter detached.');
  }

  /// As go-libp2p-pubsub: enough when the topic's FloodSub peers and mesh
  /// peers number [suggested], or `DLo` if 0, or the mesh has `DHi` peers.
  @override
  bool enoughPeers(String topic, int suggested) {
    final topicPeers = _connectedPeers().where((p) => _peerTopics[p]?.contains(topic) ?? false).toList();
    if (topicPeers.isEmpty) return false;
    final floodPeers = topicPeers.where((p) => _peerProtocols[p] == floodSubID).length;
    final meshPeers = mesh[topic]?.length ?? 0;
    if (suggested == 0) suggested = params.DLow;
    return floodPeers + meshPeers >= suggested || meshPeers >= params.DHigh;
  }

  @override
  AcceptStatus acceptFrom(PeerId peer) {
    // As go-libp2p-pubsub: the RPCs of a graylisted peer are ignored.
    if (_scoreOf(peer) < thresholds.graylistThreshold) return AcceptStatus.none;
    return _gate?.acceptFrom(peer) ?? AcceptStatus.all;
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    if (_peerProtocols.containsKey(peerId)) return;
    _log.fine('GossipSubRouter: Peer added - ${peerId.toBase58()} on $protocolId');
    _peerProtocols[peerId] = protocolId;
    // As go-libp2p-pubsub: the peer is outbound if we dialed a connection
    // to it.
    final conns = _pubsub?.host.network.connsToPeer(peerId) ?? const [];
    _outbound[peerId] = conns.any((c) => !c.stat.stats.limited && c.stat.stats.direction == Direction.outbound);
    _score?.addPeer(peerId);
    _gate?.addPeer(peerId);
    if (doPX) _fetchSignedRecord(peerId);
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.ADD_PEER
      ..addPeer = (trace_pb.TraceEvent_AddPeer()
        ..peerID = peerId.toBytes()
        ..proto = protocolId));
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    _log.fine('GossipSubRouter: Peer removed - ${peerId.toBase58()}');
    _pubsub?.removePeer(peerId);
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.REMOVE_PEER
      ..removePeer = (trace_pb.TraceEvent_RemovePeer()..peerID = peerId.toBytes()));
    for (final peers in mesh.values) {
      peers.remove(peerId);
    }
    for (final peers in fanout.values) {
      peers.remove(peerId);
    }
    _peerTopics.remove(peerId);
    if (_peerProtocols.remove(peerId) != null) _gate?.removePeer(peerId);
    _outbound.remove(peerId);
    _gossip.remove(peerId);
    _control.remove(peerId);
    _peerHave.remove(peerId);
    _iAsked.remove(peerId);
    _unwanted.remove(peerId);
    _peerDontWant.remove(peerId);
    _signedRecords.remove(peerId);
    extensions.removePeer(peerId);
    _score?.removePeer(peerId);
    _rpcQueueManagerOrNull?.peerDisconnected(peerId);
    _pubsub?.host.connManager.unprotect(peerId, 'gossipsub-mesh');
  }

  @override
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc) async {
    final Set<String> acceptedMessageIds = {};
    _log.fine('GossipSubRouter: Handling RPC from ${peerId.toBase58()} for ${rpc.toShortString()}');
    extensions.handleRpc(peerId, rpc);
    if (_pubsub?.tracing ?? false) {
      _pubsub!.traceEvent(trace_pb.TraceEvent()
        ..type = trace_pb.TraceEvent_Type.RECV_RPC
        ..recvRPC = (trace_pb.TraceEvent_RecvRPC()
          ..receivedFrom = peerId.toBytes()
          ..meta = _rpcMeta(rpc, const {})));
    }

    // Messages: drop duplicates first, then validate the new ones
    // concurrently. Subscriptions and control messages are handled below,
    // synchronously, while validation runs (see Router.handleRpc).
    final List<Future<String?>> pendingMessages = [];
    final dontWant = <String, List<String>>{};
    for (final msgProto in rpc.publish) {
      final msgIdStr = _idOf(msgProto);
      if (_isSeen(msgIdStr)) {
        _handleDuplicate(peerId, msgProto, msgIdStr);
        continue;
      }
      if (msgProto.data.length >= params.idontwantMessageThreshold) {
        dontWant.putIfAbsent(msgProto.topic, () => []).add(msgIdStr);
      }
      // The message is marked seen once its signature is verified (see
      // _validateAndForward), not before: a forged copy must not make the
      // genuine message a duplicate.
      pendingMessages.add(_validateAndForward(peerId, msgProto, msgIdStr));
    }

    _sendIDontWant(peerId, dontWant);

    for (final subOpt in rpc.subscriptions) {
      final topicId = subOpt.topicid;
      if (subOpt.subscribe) {
        _log.fine('GossipSubRouter: Received SUBSCRIBE from $peerId for topic $topicId');
        // The peer joins the mesh only through GRAFT.
        _peerTopics.putIfAbsent(peerId, () => <String>{}).add(topicId);
      } else {
        _log.fine('GossipSubRouter: Received UNSUBSCRIBE from $peerId for topic $topicId');
        _peerTopics[peerId]?.remove(topicId);
        if (mesh[topicId]?.remove(peerId) ?? false) {
          _score?.prune(peerId, topicId);
          _tracePrune(peerId, topicId);
          _unprotectIfNotInMesh(peerId);
        }
        fanout[topicId]?.remove(peerId);
      }
    }

    if (rpc.hasControl()) {
      final control = rpc.control;
      final iwant = _handleIHave(peerId, control);
      final messages = _handleIWant(peerId, control);
      final prune = _handleGraft(peerId, control);
      _handlePrune(peerId, control);
      _handleIDontWant(peerId, control);

      if (iwant.isNotEmpty || messages.isNotEmpty || prune.isNotEmpty) {
        final out = pb.RPC()..publish.addAll(messages.values);
        if (iwant.isNotEmpty || prune.isNotEmpty) {
          out.control = pb.ControlMessage()
            ..iwant.addAll(iwant)
            ..prune.addAll(prune);
        }
        _sendRpc(peerId, out, messageIds: messages.keys);
      }
    }

    for (final acceptedId in await Future.wait(pendingMessages)) {
      if (acceptedId != null) acceptedMessageIds.add(acceptedId);
    }
    return acceptedMessageIds;
  }

  /// Handles the IHAVEs of [control], as go-libp2p-pubsub's handleIHave:
  /// returns the IWANT for advertised messages we have not seen, within the
  /// per-heartbeat limits, and records a promise for one of them.
  List<pb.ControlIWant> _handleIHave(PeerId peerId, pb.ControlMessage control) {
    if (control.ihave.isEmpty) return const [];
    // Ignore the gossip of peers below the gossip threshold.
    if (_scoreOf(peerId) < thresholds.gossipThreshold) {
      _log.fine('GossipSubRouter: Ignoring IHAVE from $peerId with a score below the gossip threshold.');
      return const [];
    }
    // IHAVE flood protection.
    final have = _peerHave[peerId] = (_peerHave[peerId] ?? 0) + 1;
    if (have > params.maxIHaveMessages) {
      _log.fine('GossipSubRouter: Ignoring IHAVE from $peerId: $have IHAVEs this heartbeat.');
      return const [];
    }
    final asked = _iAsked[peerId] ?? 0;
    if (asked >= params.maxIHaveLength) {
      _log.fine('GossipSubRouter: Ignoring IHAVE from $peerId: already asked for $asked messages.');
      return const [];
    }

    final wanted = <String>{};
    for (final ihave in control.ihave) {
      if (!mesh.containsKey(ihave.topicID)) continue; // Not a joined topic.
      for (final (index, msgIdBytes) in ihave.messageIDs.indexed) {
        if (index >= params.maxIHaveLength) break;
        final msgId = messageIdFromBytes(msgIdBytes);
        if (!_isSeen(msgId)) wanted.add(msgId);
      }
    }
    if (wanted.isEmpty) return const [];

    final ask = min(wanted.length, params.maxIHaveLength - asked);
    final list = wanted.toList()..shuffle();
    final iwant = list.take(ask).toList();
    _iAsked[peerId] = asked + ask;
    _addPromise(peerId, iwant);
    _log.fine('GossipSubRouter: Requesting ${iwant.length} messages via IWANT from $peerId.');
    return [pb.ControlIWant()..messageIDs.addAll(iwant.map(messageIdToBytes))];
  }

  /// Expects [peerId] to deliver one of [msgIds] (chosen at random) within
  /// [GossipSubParams.iwantFollowupTime].
  void _addPromise(PeerId peerId, List<String> msgIds) {
    final msgId = msgIds[_random.nextInt(msgIds.length)];
    _promises.putIfAbsent(msgId, () => {}).putIfAbsent(peerId, () => clock.now().add(params.iwantFollowupTime));
  }

  /// Message [msgId] arrived: the promises for it are kept.
  void _fulfillPromise(String msgId) => _promises.remove(msgId);

  /// Ages the IDONTWANTs by one heartbeat, as go-libp2p-pubsub's
  /// clearIDontWantCounters.
  void _clearIDontWant() {
    _peerDontWant.clear();
    _unwanted.removeWhere((peer, ids) {
      ids.updateAll((id, ttl) => ttl - 1);
      ids.removeWhere((id, ttl) => ttl <= 0);
      return ids.isEmpty;
    });
  }

  /// Penalises the peers whose promises expired, as go-libp2p-pubsub's
  /// `applyIwantPenalties`.
  void _applyIwantPenalties() {
    final now = clock.now();
    final broken = <PeerId, int>{};
    _promises.removeWhere((msgId, peers) {
      peers.removeWhere((peer, expire) {
        if (!expire.isBefore(now)) return false;
        broken[peer] = (broken[peer] ?? 0) + 1;
        return true;
      });
      return peers.isEmpty;
    });
    broken.forEach((peer, count) {
      _log.fine('GossipSubRouter: $peer did not deliver $count requested messages; penalising.');
      _score?.addPenalty(peer, count);
    });
  }

  /// Sends IDONTWANT for the large messages just received to the mesh peers
  /// that speak v1.2, before validating them, as go-libp2p-pubsub's
  /// Preprocess: they need not send us copies.
  void _sendIDontWant(PeerId from, Map<String, List<String>> idsByTopic) {
    idsByTopic.forEach((topicId, ids) {
      ids.shuffle(_random);
      for (final peerId in mesh[topicId] ?? const <PeerId>{}) {
        if (peerId == from || !_supportsIDontWant(peerId)) continue;
        _sendRpc(
            peerId,
            pb.RPC()
              ..control = (pb.ControlMessage()
                ..idontwant.add(pb.ControlIDontWant()..messageIDs.addAll(ids.map(messageIdToBytes)))),
            urgent: true);
      }
    });
  }

  /// Remembers the messages [peerId] does not want, as go-libp2p-pubsub's
  /// handleIDontWant.
  void _handleIDontWant(PeerId peerId, pb.ControlMessage control) {
    if (control.idontwant.isEmpty) return;
    final count = _peerDontWant[peerId] ?? 0;
    if (count >= params.maxIDontWantMessages) {
      _log.fine('GossipSubRouter: Ignoring IDONTWANT from $peerId: too many this heartbeat.');
      return;
    }
    _peerDontWant[peerId] = count + 1;
    final unwanted = _unwanted.putIfAbsent(peerId, () => {});
    var total = 0;
    for (final idontwant in control.idontwant) {
      for (final msgIdBytes in idontwant.messageIDs) {
        if (total++ >= params.maxIDontWantLength) return;
        unwanted[messageIdFromBytes(msgIdBytes)] = params.idontwantMessageTTL;
      }
    }
  }

  bool _isUnwanted(PeerId peerId, String msgId) => _unwanted[peerId]?.containsKey(msgId) ?? false;

  /// Handles the IWANTs of [control]: returns the requested messages that
  /// we have, by ID.
  Map<String, pb.Message> _handleIWant(PeerId peerId, pb.ControlMessage control) {
    if (control.iwant.isEmpty) return const {};
    if (_scoreOf(peerId) < thresholds.gossipThreshold) {
      _log.fine('GossipSubRouter: Ignoring IWANT from $peerId with a score below the gossip threshold.');
      return const {};
    }
    // As go-libp2p-pubsub's handleIWant: each message is sent at most once
    // per IWANT, and a peer that requests a message more than
    // gossipRetransmission times is ignored for it.
    final wanted = <String, pb.Message>{};
    for (final iwantEntry in control.iwant) {
      for (final msgIdBytes in iwantEntry.messageIDs) {
        final msgId = messageIdFromBytes(msgIdBytes);
        if (wanted.containsKey(msgId) || _isUnwanted(peerId, msgId)) continue;
        final entry = _mcache.getForPeer(msgId, peerId);
        if (entry == null) continue;
        final (msg, count) = entry;
        if (count > params.gossipRetransmission) {
          _log.fine('GossipSubRouter: Peer $peerId asked for message ${messageIdToHex(msgId)} too many times; ignoring.');
          continue;
        }
        wanted[msgId] = msg;
      }
    }
    return wanted;
  }

  /// Handles the GRAFTs of [control], as go-libp2p-pubsub's handleGraft:
  /// returns the PRUNEs for the GRAFTs refused.
  List<pb.ControlPrune> _handleGraft(PeerId peerId, pb.ControlMessage control) {
    if (control.graft.isEmpty) return const [];
    final score = _scoreOf(peerId);
    final now = clock.now();
    var doPX = this.doPX;
    final prune = <String>[];
    for (final graft in control.graft) {
      final topicId = graft.topicID;
      final peers = mesh[topicId];
      if (peers == null) {
        // A GRAFT for a topic we have not joined is ignored.
        _log.fine('GossipSubRouter: Ignoring GRAFT from $peerId for topic $topicId, which we have not joined.');
        continue;
      }
      if (peers.contains(peerId)) continue;

      final backoffEnd = _backoff[topicId]?[peerId];
      if (backoffEnd != null && now.isBefore(backoffEnd)) {
        // A GRAFT during the backoff is penalised, twice if it comes soon
        // after the PRUNE, and refused with a PRUNE that renews the backoff.
        _log.fine('GossipSubRouter: GRAFT from $peerId for topic $topicId during backoff; sending PRUNE.');
        _score?.addPenalty(peerId, 1);
        doPX = false;
        final floodCutoff = backoffEnd.add(params.graftFloodThreshold - params.pruneBackoff);
        if (now.isBefore(floodCutoff)) _score?.addPenalty(peerId, 1);
        _addBackoff(peerId, topicId, params.pruneBackoff);
        prune.add(topicId);
        continue;
      }
      if (score < 0) {
        // A peer with a negative score is refused, without PX.
        _log.fine('GossipSubRouter: Refusing GRAFT from $peerId with negative score $score.');
        doPX = false;
        _addBackoff(peerId, topicId, params.pruneBackoff);
        prune.add(topicId);
        continue;
      }
      if (peers.length >= params.DHigh && !(_outbound[peerId] ?? false)) {
        // The mesh is full; inbound peers are refused, with PX.
        _addBackoff(peerId, topicId, params.pruneBackoff);
        prune.add(topicId);
        continue;
      }

      _log.fine('GossipSubRouter: Adding $peerId to the mesh of $topicId on its GRAFT.');
      peers.add(peerId);
      _score?.graft(peerId, topicId);
      _traceGraft(peerId, topicId);
      _pubsub?.host.connManager.protect(peerId, 'gossipsub-mesh');
    }
    return [for (final topicId in prune) _makePrune(peerId, topicId, doPX: doPX)];
  }

  /// Handles the PRUNEs of [control], as go-libp2p-pubsub's handlePrune.
  void _handlePrune(PeerId peerId, pb.ControlMessage control) {
    final score = _scoreOf(peerId);
    for (final prune in control.prune) {
      final topicId = prune.topicID;
      final peers = mesh[topicId];
      if (peers == null) continue;
      _log.fine('GossipSubRouter: Received PRUNE from $peerId for topic $topicId.');
      if (peers.remove(peerId)) {
        _score?.prune(peerId, topicId);
        _tracePrune(peerId, topicId);
      }
      _addBackoff(peerId, topicId, _pruneBackoffOf(prune));
      _unprotectIfNotInMesh(peerId);
      if (prune.peers.isEmpty) continue;
      // As go-libp2p-pubsub: PX from a peer with too low a score is ignored.
      if (score < thresholds.acceptPXThreshold) {
        _log.fine('GossipSubRouter: Ignoring PX from $peerId with score $score.');
        continue;
      }
      _pxConnect(prune.peers);
    }
  }

  /// Queues connections to the Peer Exchange peers [peers], as
  /// go-libp2p-pubsub's pxConnect: at most [GossipSubParams.prunePeers] of
  /// them, chosen at random, skipping the peers we already have. Peers that
  /// do not fit in [GossipSubParams.maxPendingConnections] are ignored.
  void _pxConnect(List<pb.PeerInfo> peers) {
    if (peers.length > params.prunePeers) {
      peers = (peers.toList()..shuffle(_random)).sublist(0, params.prunePeers);
    }
    final self = _pubsub?.host.id;
    for (final info in peers) {
      final PeerId peerId;
      try {
        peerId = PeerId.fromBytes(Uint8List.fromList(info.peerID));
      } catch (e) {
        _log.fine('GossipSubRouter: Ignoring PX peer with an invalid ID: $e');
        continue;
      }
      if (self == peerId || _peerProtocols.containsKey(peerId)) continue;
      if (_pxPending.length >= params.maxPendingConnections) {
        _log.fine('GossipSubRouter: Ignoring PX peer $peerId; too many pending connections.');
        continue;
      }
      _pxPending.add((peerId, info.hasSignedPeerRecord() ? info.signedPeerRecord : null));
    }
    while (_pxConnecting < params.connectors && _pxPending.isNotEmpty) {
      _pxConnecting++;
      _pxConnector().whenComplete(() => _pxConnecting--);
    }
  }

  /// Connects to the queued Peer Exchange peers until none are left, as
  /// go-libp2p-pubsub's connector.
  Future<void> _pxConnector() async {
    while (_pxPending.isNotEmpty) {
      final (peerId, record) = _pxPending.removeFirst();
      final host = _pubsub?.host;
      if (host == null) return;
      try {
        if (host.network.connectedness(peerId) == Connectedness.connected) continue;
        if (record != null && !await _consumePeerRecord(peerId, record)) continue;
        final addrs = await host.peerStore.addrBook.addrs(peerId);
        _log.fine('GossipSubRouter: Connecting to PX peer $peerId at $addrs.');
        await host.connect(AddrInfo(peerId, addrs)).timeout(params.connectionTimeout);
      } catch (e) {
        _log.fine('GossipSubRouter: Error connecting to PX peer $peerId: $e');
      }
    }
  }

  /// Checks the signed peer record [bytes] of the PX peer [peerId] and
  /// stores its addresses, as go-libp2p-pubsub's pxConnect and connector.
  /// Returns false if the record is invalid, so the peer is skipped.
  Future<bool> _consumePeerRecord(PeerId peerId, List<int> bytes) async {
    final Envelope envelope;
    try {
      final (env, record) = await Envelope.consumeEnvelope(Uint8List.fromList(bytes), PeerRecordEnvelopeDomain);
      // The record must be about the peer and signed by its key.
      if (record is! PeerRecord || record.peerId != peerId || PeerId.fromPublicKey(env.publicKey) != peerId) {
        _log.fine('GossipSubRouter: Bogus peer record from PX for $peerId.');
        return false;
      }
      envelope = env;
    } catch (e) {
      _log.fine('GossipSubRouter: Invalid peer record from PX for $peerId: $e');
      return false;
    }
    final (ok, cab) = getCertifiedAddrBook(_pubsub?.host.peerStore.addrBook);
    if (ok) {
      try {
        await cab!.consumePeerRecord(envelope, AddressTTL.tempAddrTTL);
      } catch (e) {
        _log.fine('GossipSubRouter: Error storing peer record of $peerId: $e');
      }
    }
    return true;
  }

  /// Fetches the signed peer record of [peerId] for our Peer Exchange.
  void _fetchSignedRecord(PeerId peerId) {
    final (ok, cab) = getCertifiedAddrBook(_pubsub?.host.peerStore.addrBook);
    if (!ok) return;
    () async {
      final envelope = await cab!.getPeerRecord(peerId);
      if (envelope == null || !_peerProtocols.containsKey(peerId)) return;
      _signedRecords[peerId] = await envelope.marshal();
    }().catchError((Object e) {
      _log.fine('GossipSubRouter: Error fetching the peer record of $peerId: $e');
    });
  }

  /// The backoff that a received PRUNE asks for: [GossipSubParams.pruneBackoff]
  /// if it has none, capped to [GossipSubParams.maxPruneBackoff]. The backoff
  /// is a uint64 that protobuf decodes as a signed Int64, so a value of 2^63
  /// or more reads as negative; it is capped too.
  Duration _pruneBackoffOf(pb.ControlPrune prune) {
    if (!prune.hasBackoff() || prune.backoff == Int64.ZERO) return params.pruneBackoff;
    final maxSeconds = Int64(params.maxPruneBackoff.inSeconds);
    final seconds = prune.backoff.isNegative || prune.backoff > maxSeconds ? maxSeconds : prune.backoff;
    return Duration(seconds: seconds.toInt());
  }

  /// Handles a message that was seen before.
  void _handleDuplicate(PeerId peerId, pb.Message msgProto, String msgIdStr) {
    _log.fine('GossipSubRouter: Received duplicate message ${messageIdToHex(msgIdStr)} from $peerId. Ignoring.');
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE
      ..duplicateMessage = (trace_pb.TraceEvent_DuplicateMessage()
        ..messageID = messageIdToBytes(msgIdStr)
        ..receivedFrom = peerId.toBytes()
        ..topic = msgProto.topic));
    // The scorer credits a mesh peer for a timely copy, and penalises a
    // copy of an invalid message.
    _score?.duplicateMessage(msgIdStr, peerId, msgProto.topic);
    _gate?.duplicateMessage(peerId);
  }

  /// Validates a new message from [peerId]. If the message is accepted, puts
  /// it in the message cache, forwards it and returns its ID; otherwise
  /// returns null.
  ///
  /// The message is marked seen when its signature has been verified. A copy
  /// that was marked seen first, while this one was being checked, makes
  /// this one a duplicate. As in go-libp2p-pubsub, a message that fails the
  /// structure or signature checks penalises [peerId] but is not tracked:
  /// its ID may be a forgery of a genuine message's ID.
  Future<String?> _validateAndForward(PeerId peerId, pb.Message msgProto, String msgIdStr) async {
    final pubsub = _pubsub;
    if (pubsub == null) return null;
    final topicId = msgProto.topic;

    var signatureVerified = false;
    var duplicate = false;
    bool markSeen() {
      signatureVerified = true;
      if (_isSeen(msgIdStr)) {
        duplicate = true;
        return false;
      }
      _seenMessages.add(msgIdStr);
      _score?.validateMessage(msgIdStr);
      _gate?.validateMessage();
      _fulfillPromise(msgIdStr);
      return true;
    }

    ValidationResult validationResult;
    try {
      validationResult = await pubsub.validateMessage(
          PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId),
          markSeen: markSeen,
          onReject: _gate == null ? null : (reason) => _gate?.rejectMessage(peerId, reason));
    } catch (e) {
      _log.warning('GossipSubRouter: Validation of message ${messageIdToHex(msgIdStr)} from $peerId failed with an error: $e. Dropping.');
      return null;
    }
    if (_pubsub == null) return null; // Detached while the message was in validation.
    if (duplicate) {
      _handleDuplicate(peerId, msgProto, msgIdStr);
      return null;
    }

    switch (validationResult) {
      case ValidationResult.reject:
        _log.fine('GossipSubRouter: Message ${messageIdToHex(msgIdStr)} from $peerId rejected.');
        _score?.rejectMessage(msgIdStr, peerId, topicId,
            signatureVerified ? RejectReason.validationFailed : RejectReason.invalidSignature);
        return null;
      case ValidationResult.ignore:
        _log.fine('GossipSubRouter: Message ${messageIdToHex(msgIdStr)} from $peerId ignored by validation.');
        // Not marked seen: dropped by the global throttle, before checks.
        if (signatureVerified) {
          _score?.rejectMessage(msgIdStr, peerId, topicId, RejectReason.validationIgnored);
        }
        return null;
      case ValidationResult.accept:
        break;
    }
    if (!signatureVerified && !markSeen()) {
      // Accepted without markSeen being called (a PubSub that does not
      // support it); keep the seen cache right anyway.
      _handleDuplicate(peerId, msgProto, msgIdStr);
      return null;
    }

    _mcache.put(msgIdStr, msgProto);
    _score?.deliverMessage(msgIdStr, peerId, topicId);
    _gate?.deliverMessage(peerId, topicId);
    _fulfillPromise(msgIdStr);
    pubsub.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.DELIVER_MESSAGE
      ..deliverMessage = (trace_pb.TraceEvent_DeliverMessage()
        ..messageID = messageIdToBytes(msgIdStr)
        ..receivedFrom = peerId.toBytes()
        ..topic = topicId));

    _forward(msgProto, msgIdStr, from: peerId);
    // PubSub delivers the message to local subscribers after handleRpc
    // returns, for the IDs that this method accepted.
    return msgIdStr;
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final pubsub = _pubsub;
    if (pubsub == null) {
      _log.warning('GossipSubRouter: PubSub not attached. Cannot publish.');
      return;
    }
    final msgIdStr = _idOf(message.rpcMessage);
    _mcache.put(msgIdStr, message.rpcMessage);
    _seenMessages.add(msgIdStr);
    _forward(message.rpcMessage, msgIdStr, from: message.receivedFrom ?? pubsub.host.id);
  }

  /// Sends message [msg] to the peers of its topic, as go-libp2p-pubsub's
  /// `GossipSubRouter.Publish`: flood publish for our own messages (when
  /// [GossipSubParams.floodPublish]), otherwise the mesh, or the fanout for a
  /// topic we have not joined. [from] (the peer we got the message from) and
  /// the message's author are skipped.
  void _forward(pb.Message msg, String msgIdStr, {required PeerId from}) {
    final pubsub = _pubsub;
    if (pubsub == null) return;
    final topicId = msg.topic;
    final local = from == pubsub.host.id;
    final toSend = <PeerId>{};

    if (local && params.floodPublish) {
      toSend.addAll(_connectedTopicPeers(topicId).where((p) => _scoreOf(p) >= thresholds.publishThreshold));
    } else {
      // FloodSub peers get every message of their topics.
      toSend.addAll(_connectedTopicPeers(topicId)
          .where((p) => !_supportsMesh(p) && _scoreOf(p) >= thresholds.publishThreshold));
      var peers = mesh[topicId];
      if (peers == null) {
        // Not joined: use the fanout, creating it if needed.
        peers = fanout[topicId];
        if (peers == null || peers.isEmpty) {
          peers = _getPeers(topicId, params.D, (p) => _scoreOf(p) >= thresholds.publishThreshold).toSet();
          if (peers.isNotEmpty) fanout[topicId] = peers;
        }
        fanoutLastPublished[topicId] = clock.now();
      }
      toSend.addAll(peers.where((p) => !_isUnwanted(p, msgIdStr)));
    }

    final author = _authorOf(msg);
    final rpc = pb.RPC()..publish.add(msg);
    for (final peerId in toSend) {
      if (peerId == from || peerId == author) continue;
      _sendRpc(peerId, rpc, messageIds: [msgIdStr]);
    }
  }

  PeerId? _authorOf(pb.Message msg) {
    if (msg.from.isEmpty) return null;
    try {
      return PeerId.fromBytes(Uint8List.fromList(msg.from));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> join(Topic topic) async {
    final topicId = topic.name;
    if (mesh.containsKey(topicId)) return;
    _log.fine('GossipSubRouter: Joining topic $topicId');
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.JOIN
      ..join = (trace_pb.TraceEvent_Join()..topic = topicId));

    // As go-libp2p-pubsub: the mesh starts from the fanout of the topic,
    // without its peers with a negative score or in backoff, and is filled
    // up to D with other peers of the topic.
    final peers = fanout.remove(topicId) ?? <PeerId>{};
    fanoutLastPublished.remove(topicId);
    final connected = _connectedPeers();
    peers.removeWhere((p) => !connected.contains(p) || _scoreOf(p) < 0 || _inBackoff(p, topicId));
    if (peers.length < params.D) {
      peers.addAll(_getPeers(topicId, params.D - peers.length,
          (p) => !peers.contains(p) && !_inBackoff(p, topicId) && _scoreOf(p) >= 0));
    }
    mesh[topicId] = peers;
    for (final peerId in peers) {
      _log.fine('GossipSubRouter: join: Sending GRAFT to ${peerId.toBase58()} for topic $topicId.');
      _score?.graft(peerId, topicId);
      _traceGraft(peerId, topicId);
      _sendControl(peerId, pb.ControlMessage()..graft.add(pb.ControlGraft()..topicID = topicId));
      _pubsub?.host.connManager.protect(peerId, 'gossipsub-mesh');
    }
  }

  @override
  Future<void> leave(Topic topic) async {
    final topicId = topic.name;
    final peers = mesh.remove(topicId);
    if (peers == null) return;
    _log.fine('GossipSubRouter: Leaving topic $topicId');
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.LEAVE
      ..leave = (trace_pb.TraceEvent_Leave()..topic = topicId));
    for (final peerId in peers) {
      _log.fine('GossipSubRouter: leave: Sending PRUNE to ${peerId.toBase58()} for topic $topicId.');
      _score?.prune(peerId, topicId);
      _tracePrune(peerId, topicId);
      _sendControl(peerId, pb.ControlMessage()..prune.add(_makePrune(peerId, topicId, doPX: doPX, unsubscribe: true)));
      // Do not GRAFT the peer again for the backoff if we rejoin.
      _addBackoff(peerId, topicId, params.unsubscribeBackoff);
      _unprotectIfNotInMesh(peerId);
    }
  }

  @override
  Future<void> start() async {
    // The heartbeat shifts the message cache.
    _score?.start();
    _gate?.start();
    _heartbeatTimer?.cancel();
    _heartbeatTicks = 0;
    // The first heartbeat after the initial delay, then one every heartbeat
    // interval.
    _heartbeatTimer = Timer(params.heartbeatInitialDelay, () {
      _heartbeatTimer = Timer.periodic(params.heartbeatInterval, (_) => _heartbeat());
      _heartbeat();
    });
    _log.fine('GossipSubRouter started.');
  }

  /// Stops the heartbeat and forgets the peers, meshes and fanouts, so that
  /// [start] begins afresh: [PubSub.start] joins the subscribed topics
  /// again and adds the peers again.
  @override
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final peerId in {..._peerProtocols.keys, ..._peerTopics.keys}) {
      await removePeer(peerId);
    }
    mesh.clear();
    fanout.clear();
    fanoutLastPublished.clear();
    _backoff.clear();
    _promises.clear();
    _pxPending.clear();
    _signedRecords.clear();
    _rpcQueueManagerOrNull?.clearAll();
    _score?.stop();
    _gate?.stop();
    _seenMessages.clear();
    _log.fine('GossipSubRouter stopped.');
  }

  bool _isPeerInAnyMesh(PeerId peerId) => mesh.values.any((peers) => peers.contains(peerId));

  void _unprotectIfNotInMesh(PeerId peerId) {
    if (!_isPeerInAnyMesh(peerId)) {
      _pubsub?.host.connManager.unprotect(peerId, 'gossipsub-mesh');
    }
  }

  Set<PeerId> _connectedPeers() => _pubsub?.host.network.peers.toSet() ?? <PeerId>{};

  /// The connected peers known to be subscribed to [topicId], except us.
  List<PeerId> _connectedTopicPeers(String topicId) {
    final connected = _connectedPeers();
    final self = _pubsub?.host.id;
    return [
      for (final entry in _peerTopics.entries)
        if (entry.value.contains(topicId) && connected.contains(entry.key) && entry.key != self) entry.key,
    ];
  }

  /// Up to [count] random connected peers of [topicId] that pass [filter],
  /// as go-libp2p-pubsub's `getPeers`.
  List<PeerId> _getPeers(String topicId, int count, bool Function(PeerId) filter) {
    final peers = _connectedTopicPeers(topicId).where((p) => _supportsMesh(p) && filter(p)).toList()..shuffle();
    return peers.take(count).toList();
  }

  /// Starts a backoff of [duration] for [peerId] on [topicId], unless one
  /// that ends later is running.
  void _addBackoff(PeerId peerId, String topicId, Duration duration) {
    final end = clock.now().add(duration);
    final topicBackoff = _backoff.putIfAbsent(topicId, () => {});
    final current = topicBackoff[peerId];
    if (current == null || current.isBefore(end)) {
      topicBackoff[peerId] = end;
    }
  }

  /// Whether [peerId] must not be GRAFTed on [topicId]. As go-libp2p-pubsub,
  /// this holds until the entry is cleared, two heartbeats after the end of
  /// the backoff, so that our GRAFT does not land in the remote peer's
  /// backoff.
  bool _inBackoff(PeerId peerId, String topicId) => _backoff[topicId]?.containsKey(peerId) ?? false;

  /// Clears the backoffs that ended more than two heartbeats ago, every 15
  /// heartbeats, as go-libp2p-pubsub's `clearBackoff`.
  void _clearBackoff() {
    if (_heartbeatTicks % 15 != 0) return;
    final now = clock.now();
    final slack = params.heartbeatInterval * 2;
    _backoff.removeWhere((topic, peers) {
      peers.removeWhere((peer, end) => end.add(slack).isBefore(now));
      return peers.isEmpty;
    });
  }

  /// A PRUNE for [topicId] to [peerId], as go-libp2p-pubsub's `makePrune`.
  /// With [doPX], it carries up to [GossipSubParams.prunePeers] other peers
  /// of the topic with a score >= 0, for Peer Exchange.
  pb.ControlPrune _makePrune(PeerId peerId, String topicId, {required bool doPX, bool unsubscribe = false}) {
    final prune = pb.ControlPrune()..topicID = topicId;
    // A v1.0 peer knows neither backoff nor PX.
    if (!_supportsPX(peerId)) return prune;
    final backoff = unsubscribe ? params.unsubscribeBackoff : params.pruneBackoff;
    prune.backoff = Int64(backoff.inSeconds);
    if (doPX) {
      for (final px in _getPeers(topicId, params.prunePeers, (p) => p != peerId && _scoreOf(p) >= 0)) {
        // As go-libp2p-pubsub: with the peer's signed record, if we have it.
        final info = pb.PeerInfo()..peerID = px.toBytes();
        final record = _signedRecords[px];
        if (record != null) {
          info.signedPeerRecord = record;
        } else {
          _fetchSignedRecord(px); // For the next PRUNE.
        }
        prune.peers.add(info);
      }
    }
    return prune;
  }

  void _traceGraft(PeerId peerId, String topicId) {
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.GRAFT
      ..graft = (trace_pb.TraceEvent_Graft()
        ..peerID = peerId.toBytes()
        ..topic = topicId));
  }

  void _tracePrune(PeerId peerId, String topicId) {
    _pubsub?.traceEvent(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.PRUNE
      ..prune = (trace_pb.TraceEvent_Prune()
        ..peerID = peerId.toBytes()
        ..topic = topicId));
  }

  void _sendControl(PeerId peerId, pb.ControlMessage control) {
    _sendRpc(peerId, pb.RPC()..control = control);
  }

  /// Queues [rpc] for [peerId] and traces it, as go-libp2p-pubsub's
  /// `sendRPC`: pending gossip and control for the peer ride along. Parts
  /// that cannot be queued are dropped, traced as DROP_RPC, and their GRAFTs
  /// and PRUNEs kept to retry. [messageIds] are the IDs of the messages in
  /// [rpc], for the trace.
  void _sendRpc(PeerId peerId, pb.RPC rpc, {Iterable<String> messageIds = const [], bool urgent = false}) {
    final queue = _rpcQueueManagerOrNull;
    if (queue == null) return;
    _piggyback(peerId, rpc);
    final ids = messageIds.toList();
    final idOf = Map<pb.Message, String>.identity();
    for (var i = 0; i < rpc.publish.length && i < ids.length; i++) {
      idOf[rpc.publish[i]] = ids[i];
    }
    for (final (part, queued) in queue.sendRpc(peerId, rpc, protocolId: gossipSubIDv11, urgent: urgent)) {
      _trace(peerId, part, idOf, dropped: !queued);
      if (!queued && part.hasControl()) _pushControl(peerId, part.control);
    }
  }

  void _trace(PeerId peerId, pb.RPC rpc, Map<pb.Message, String> idOf, {required bool dropped}) {
    if (!(_pubsub?.tracing ?? false)) return;
    final meta = _rpcMeta(rpc, idOf);
    final event = trace_pb.TraceEvent();
    if (dropped) {
      event
        ..type = trace_pb.TraceEvent_Type.DROP_RPC
        ..dropRPC = (trace_pb.TraceEvent_DropRPC()
          ..sendTo = peerId.toBytes()
          ..meta = meta);
    } else {
      event
        ..type = trace_pb.TraceEvent_Type.SEND_RPC
        ..sendRPC = (trace_pb.TraceEvent_SendRPC()
          ..sendTo = peerId.toBytes()
          ..meta = meta);
    }
    _pubsub?.traceEvent(event);
  }

  /// Adds the pending gossip and control of [peerId] to [rpc], as
  /// go-libp2p-pubsub's piggybackGossip and piggybackControl. A pending
  /// GRAFT is kept only if the peer is still in the mesh, a PRUNE only if it
  /// is not.
  void _piggyback(PeerId peerId, pb.RPC rpc) {
    final gossip = _gossip.remove(peerId);
    final control = _control.remove(peerId);
    if (gossip == null && control == null) return;
    final out = rpc.ensureControl();
    if (gossip != null) out.ihave.addAll(gossip);
    if (control != null) {
      out.graft.addAll(control.graft.where((g) => mesh[g.topicID]?.contains(peerId) ?? false));
      out.prune.addAll(control.prune.where((p) => !(mesh[p.topicID]?.contains(peerId) ?? false)));
    }
  }

  /// Keeps the GRAFTs and PRUNEs of a dropped RPC to retry, as
  /// go-libp2p-pubsub's pushControl.
  void _pushControl(PeerId peerId, pb.ControlMessage control) {
    if (control.graft.isEmpty && control.prune.isEmpty) return;
    _control.putIfAbsent(peerId, pb.ControlMessage.new)
      ..graft.addAll(control.graft)
      ..prune.addAll(control.prune);
  }

  /// Queues IHAVE gossip for [peerId], sent with its next RPC or at the end
  /// of the heartbeat.
  void _enqueueGossip(PeerId peerId, pb.ControlIHave ihave) {
    _gossip.putIfAbsent(peerId, () => []).add(ihave);
  }

  /// Gossips the recent messages of [topicId] (IHAVE) to [DLazy] or
  /// [gossipFactor] of its peers, except [exclude], as go-libp2p-pubsub's
  /// emitGossip.
  void _emitGossip(String topicId, Set<PeerId> exclude) {
    var ids = _mcache.getGossipIds(topicId);
    if (ids.isEmpty) return;
    ids.shuffle(_random);
    if (ids.length > params.maxIHaveLength) ids = ids.sublist(0, params.maxIHaveLength);

    final peers = _connectedTopicPeers(topicId)
        .where((p) => !exclude.contains(p) && _supportsMesh(p) && _scoreOf(p) >= thresholds.gossipThreshold)
        .toList()
      ..shuffle(_random);
    final target = min(max(params.DLazy, (params.gossipFactor * peers.length).floor()), peers.length);
    final ihave = pb.ControlIHave()
      ..topicID = topicId
      ..messageIDs.addAll(ids.map(messageIdToBytes));
    for (final peerId in peers.take(target)) {
      _enqueueGossip(peerId, ihave);
    }
  }

  /// Sends the gossip still pending at the end of the heartbeat.
  void _flushGossip() {
    for (final peerId in _gossip.keys.toList()) {
      if (_gossip.containsKey(peerId)) _sendRpc(peerId, pb.RPC());
    }
  }

  /// The trace summary of [rpc], as go-libp2p-pubsub's traceRPCMeta.
  /// [idOf] holds the IDs of messages already computed.
  trace_pb.TraceEvent_RPCMeta _rpcMeta(pb.RPC rpc, Map<pb.Message, String> idOf) {
    final meta = trace_pb.TraceEvent_RPCMeta();
    for (final msg in rpc.publish) {
      final id = idOf[msg] ?? _idOf(msg);
      meta.messages.add(trace_pb.TraceEvent_MessageMeta()
        ..messageID = messageIdToBytes(id)
        ..topic = msg.topic);
    }
    for (final sub in rpc.subscriptions) {
      meta.subscription.add(trace_pb.TraceEvent_SubMeta()
        ..subscribe = sub.subscribe
        ..topic = sub.topicid);
    }
    if (rpc.hasControl()) meta.control = _controlMeta(rpc.control);
    return meta;
  }

  static trace_pb.TraceEvent_ControlMeta _controlMeta(pb.ControlMessage control) {
    return trace_pb.TraceEvent_ControlMeta()
      ..ihave.addAll(control.ihave.map((i) => trace_pb.TraceEvent_ControlIHaveMeta()
        ..topic = i.topicID
        ..messageIDs.addAll(i.messageIDs)))
      ..iwant.addAll(control.iwant.map((i) => trace_pb.TraceEvent_ControlIWantMeta()..messageIDs.addAll(i.messageIDs)))
      ..graft.addAll(control.graft.map((g) => trace_pb.TraceEvent_ControlGraftMeta()..topic = g.topicID))
      ..prune.addAll(control.prune.map((p) => trace_pb.TraceEvent_ControlPruneMeta()
        ..topic = p.topicID
        ..peers.addAll(p.peers.map((px) => px.peerID))))
      ..idontwant.addAll(control.idontwant.map((i) => trace_pb.TraceEvent_ControlIDontWantMeta()..messageIDs.addAll(i.messageIDs)));
  }

  /// The heartbeat, as go-libp2p-pubsub's: maintains each mesh and fanout,
  /// then sends the GRAFTs and PRUNEs, one RPC per peer.
  void _heartbeat() {
    _heartbeatTicks++;

    // Forget the peers that are no longer connected. PubSub also reports
    // disconnects as they happen, but the host does not report all of them.
    final connected = _connectedPeers();
    final knownPeers = <PeerId>{
      ..._peerTopics.keys,
      for (final peers in mesh.values) ...peers,
      for (final peers in fanout.values) ...peers,
    };
    for (final peerId in knownPeers.where((p) => !connected.contains(p))) {
      _log.fine('Heartbeat: Removing disconnected peer ${peerId.toBase58()}');
      removePeer(peerId);
    }

    _clearBackoff();
    _peerHave.clear();
    _iAsked.clear();
    _clearIDontWant();
    _applyIwantPenalties();

    final scores = <PeerId, double>{};
    double score(PeerId p) => scores.putIfAbsent(p, () => _scoreOf(p));

    final toGraft = <PeerId, List<String>>{};
    final toPrune = <PeerId, List<String>>{};
    final noPX = <PeerId>{};

    mesh.forEach((topicId, peers) {
      void prunePeer(PeerId p) {
        _score?.prune(p, topicId);
        _tracePrune(p, topicId);
        peers.remove(p);
        _addBackoff(p, topicId, params.pruneBackoff);
        toPrune.putIfAbsent(p, () => []).add(topicId);
      }

      void graftPeer(PeerId p) {
        _score?.graft(p, topicId);
        _traceGraft(p, topicId);
        peers.add(p);
        toGraft.putIfAbsent(p, () => []).add(topicId);
      }

      // Drop the peers with a negative score, without PX.
      for (final p in peers.where((p) => score(p) < 0).toList()) {
        _log.fine('Heartbeat: Pruning ${p.toBase58()} with negative score from $topicId.');
        prunePeer(p);
        noPX.add(p);
      }

      // Too few peers: GRAFT more.
      if (peers.length < params.DLow) {
        _getPeers(topicId, params.D - peers.length,
                (p) => !peers.contains(p) && !_inBackoff(p, topicId) && score(p) >= 0)
            .forEach(graftPeer);
      }

      // Too many peers: keep the DScore best, then random ones, keeping
      // DOut outbound peers, and PRUNE the rest.
      if (peers.length >= params.DHigh) {
        final plst = peers.toList()..shuffle();
        plst.sort((a, b) => score(b).compareTo(score(a)));
        final rest = plst.sublist(params.DScore)..shuffle();
        plst.replaceRange(params.DScore, plst.length, rest);

        bool isOutbound(PeerId p) => _outbound[p] ?? false;
        final outbound = plst.take(params.D).where(isOutbound).length;
        if (outbound < params.DOut) {
          // Move the outbound peers to the front, so they are kept.
          void rotate(int i) => plst.insert(0, plst.removeAt(i));

          if (outbound > 0) {
            var have = outbound;
            for (var i = 1; i < params.D && have > 0; i++) {
              if (isOutbound(plst[i])) {
                rotate(i);
                have--;
              }
            }
          }
          var need = params.DOut - outbound;
          for (var i = params.D; i < plst.length && need > 0; i++) {
            if (isOutbound(plst[i])) {
              rotate(i);
              need--;
            }
          }
        }
        for (final p in plst.sublist(params.D)) {
          prunePeer(p);
        }
      }

      // Enough peers but too few outbound ones: GRAFT outbound peers.
      if (peers.length >= params.DLow) {
        final outbound = peers.where((p) => _outbound[p] ?? false).length;
        if (outbound < params.DOut) {
          _getPeers(
                  topicId,
                  params.DOut - outbound,
                  (p) => !peers.contains(p) && !_inBackoff(p, topicId) && (_outbound[p] ?? false) && score(p) >= 0)
              .forEach(graftPeer);
        }
      }

      // Opportunistic grafting: when the median score of the mesh is below
      // the threshold, GRAFT a few peers that score above it.
      if (_heartbeatTicks % params.opportunisticGraftTicks == 0 && peers.length > 1) {
        final sorted = peers.toList()..sort((a, b) => score(a).compareTo(score(b)));
        final medianScore = score(sorted[sorted.length ~/ 2]);
        if (medianScore < thresholds.opportunisticGraftThreshold) {
          for (final p in _getPeers(topicId, params.opportunisticGraftPeers,
              (p) => !peers.contains(p) && !_inBackoff(p, topicId) && score(p) > medianScore)) {
            _log.fine('Heartbeat: Opportunistically grafting ${p.toBase58()} on $topicId.');
            graftPeer(p);
          }
        }
      }

      _emitGossip(topicId, peers);
    });

    // Expire the fanout of the topics we have not published to for the
    // fanout TTL.
    final now = clock.now();
    fanoutLastPublished.removeWhere((topicId, lastPub) {
      if (now.difference(lastPub) <= params.fanoutTTL) return false;
      _log.fine('Heartbeat: Fanout TTL expired for topic $topicId.');
      fanout.remove(topicId);
      return true;
    });

    // Maintain the fanouts: drop the peers no longer in the topic or below
    // the publish threshold, and fill them up to D.
    fanout.forEach((topicId, peers) {
      final topicPeers = _connectedTopicPeers(topicId).toSet();
      peers.removeWhere((p) => !topicPeers.contains(p) || score(p) < thresholds.publishThreshold);
      if (peers.length < params.D) {
        peers.addAll(_getPeers(topicId, params.D - peers.length,
            (p) => !peers.contains(p) && score(p) >= thresholds.publishThreshold));
      }
      _emitGossip(topicId, peers);
    });

    _sendGraftPrune(toGraft, toPrune, noPX);
    _flushGossip();
    _mcache.shift();
  }

  /// Sends the GRAFTs and PRUNEs of the heartbeat, one RPC per peer.
  void _sendGraftPrune(Map<PeerId, List<String>> toGraft, Map<PeerId, List<String>> toPrune, Set<PeerId> noPX) {
    for (final peerId in {...toGraft.keys, ...toPrune.keys}) {
      final control = pb.ControlMessage();
      for (final topicId in toGraft[peerId] ?? const <String>[]) {
        control.graft.add(pb.ControlGraft()..topicID = topicId);
        _pubsub?.host.connManager.protect(peerId, 'gossipsub-mesh');
      }
      for (final topicId in toPrune[peerId] ?? const <String>[]) {
        control.prune.add(_makePrune(peerId, topicId, doPX: doPX && !noPX.contains(peerId)));
      }
      if (toPrune.containsKey(peerId)) _unprotectIfNotInMesh(peerId);
      _sendControl(peerId, control);
    }
  }
}

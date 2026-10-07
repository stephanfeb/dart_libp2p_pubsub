import 'dart:async';
import 'dart:math';
import 'dart:typed_data'; // Added explicit import for Uint8List

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:fixnum/fixnum.dart';

import '../core/pubsub.dart';
import '../core/message.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/topic.dart';
import '../core/router.dart'; // Import the Router interface
import '../core/comm.dart'; // For PubSubProtocol, RpcShortString extension and gossipSubIDv11
import 'rpc_queue.dart'; // For RpcOutgoingQueueManager
import 'mcache.dart'; // For MessageCache
import '../pb/trace.pb.dart' as trace_pb; // For trace event types
import '../util/midgen.dart'; // For defaultMessageIdFn
import '../util/timecache.dart'; // For FirstSeenCache
import 'package:logging/logging.dart';

final _log = Logger('GossipSubRouter');

// Placeholder for GossipSub parameters
// TODO: Define this class properly with all GossipSub configurable values.
class GossipSubParams {
  // Degree of the mesh (target number of peers in mesh for a topic)
  final int D;
  // Lower bound for mesh degree
  final int DLow;
  // Upper bound for mesh degree
  final int DHigh;
  // Score threshold to be in themesh
  final double DScore;
  // Time to live for fanout peers
  final Duration fanoutTTL;
  // Number of peers to send IHAVE messages to (for topics we are not meshed on)
  final int DLazy;
  // Number of peers to include in PRUNE messages for Peer Exchange (PX).
  final int prunePeers;
  // Score threshold for opportunistic grafting.
  final double opportunisticGraftScoreThreshold;
  /// How long the router remembers the ID of a message it has seen
  /// (go-libp2p-pubsub's `TimeCacheDuration`). A copy of a message that
  /// arrives within this time is dropped as a duplicate without validation.
  final Duration seenMessagesTTL;
  /// Time between heartbeats, which maintain the mesh and the fanout
  /// (go-libp2p-pubsub's `GossipSubHeartbeatInterval`).
  final Duration heartbeatInterval;
  /// Time from [GossipSubRouter.start] to the first heartbeat
  /// (go-libp2p-pubsub's `GossipSubHeartbeatInitialDelay`).
  final Duration heartbeatInitialDelay;
  /// Opportunistic grafting runs once every this many heartbeats
  /// (go-libp2p-pubsub's `GossipSubOpportunisticGraftTicks`).
  final int opportunisticGraftTicks;
  /// Backoff sent in the PRUNE messages of [GossipSubRouter.leave], asking
  /// the pruned peers not to GRAFT us again for this time
  /// (go-libp2p-pubsub's `GossipSubUnsubscribeBackoff`).
  final Duration unsubscribeBackoff;
  // etc.

  GossipSubParams({
    this.D = 6,
    this.DLow = 4,
    this.DHigh = 12,
    this.DScore = 0.0, // Default score threshold to be in mesh
    this.fanoutTTL = const Duration(minutes: 1),
    this.DLazy = 6, // Default number of peers for IHAVE gossip
    this.prunePeers = 5, // Default number of peers for PX in PRUNE
    this.opportunisticGraftScoreThreshold = 10.0, // Default score for opportunistic grafting
    this.seenMessagesTTL = const Duration(minutes: 2),
    this.heartbeatInterval = const Duration(seconds: 1),
    this.heartbeatInitialDelay = const Duration(milliseconds: 100),
    this.opportunisticGraftTicks = 60,
    this.unsubscribeBackoff = const Duration(seconds: 10),
  }) : assert(opportunisticGraftTicks > 0);

  static GossipSubParams get defaultParams => GossipSubParams();
}

/// Implementation of the GossipSub_v1.1 routing protocol.
class GossipSubRouter implements Router {
  PubSub? _pubsub; // Reference to the PubSub instance
  late final GossipSubParams params;
  late final RpcOutgoingQueueManager _rpcQueueManager;
  late final MessageCache _mcache;

  /// IDs of the messages seen recently, whatever their validation result.
  /// A message is marked here before validation, so its duplicates are not
  /// validated again.
  late final FirstSeenCache<String> _seenMessages;

  /// IDs of the messages that failed validation with reject. A peer that
  /// sends a duplicate of such a message is penalised too.
  late final FirstSeenCache<String> _rejectedMessages;

  static const int _seenMessagesCapacity = 1 << 17;

  /// Peers in the mesh, per topic. Mesh peers are those we have an explicit
  /// bidirectional link with for a topic, used for full message propagation.
  /// topic -> set of peer IDs
  final Map<String, Set<PeerId>> mesh = {};

  /// Peers in the fanout set, per topic. Fanout peers are those we publish to
  /// for topics we are not subscribed to (i.e., not in their mesh).
  /// This is used to ensure messages reach the network even if we are not
  /// maintaining a full mesh for the topic.
  /// topic -> set of peer IDs
  final Map<String, Set<PeerId>> fanout = {};

  /// Tracks the last time we published to a fanout topic.
  /// Used to expire fanout peers if we haven't published to the topic recently.
  /// topic -> DateTime
  final Map<String, DateTime> fanoutLastPublished = {};

  /// Tracks which topics each peer is subscribed to.
  final Map<PeerId, Set<String>> _peerTopics = {};

  // TODO: Add other GossipSub specific fields:
  // - Seen cache (for IHAVE messages / control message IDs)
  // - Peer scores
  Timer? _heartbeatTimer;
  /// Number of heartbeats since [start].
  int _heartbeatTicks = 0;
  // - Outbound RPC queues per peer
  // - etc.

  /// Returns true if the router has been started and the heartbeat is active.
  bool get isStarted => _heartbeatTimer != null;

  GossipSubRouter({GossipSubParams? params}) {
    this.params = params ?? GossipSubParams.defaultParams;
    _mcache = MessageCache(
        // TODO: Consider passing cache parameters from GossipSubParams
        );
    _seenMessages = FirstSeenCache<String>(this.params.seenMessagesTTL, _seenMessagesCapacity);
    _rejectedMessages = FirstSeenCache<String>(this.params.seenMessagesTTL, _seenMessagesCapacity);
  }

  bool _isSeen(String msgId) => _seenMessages.contains(msgId) || _mcache.seen(msgId);

  @override
  Future<void> attach(PubSub pubsub) async {
    _pubsub = pubsub;
    // Ensure _pubsub is not null before trying to access its properties
    // final hostIdString = _pubsub?.host?.id?.toBase58() ?? "null (pubsub or host is null)"; // Removed debug line
    // print('[DEBUG] GossipSubRouter.attach: _pubsub is now ${(_pubsub == null ? "null" : "set")}, host is $hostIdString'); // Removed debug line
    if (_pubsub != null) {
      _rpcQueueManager = RpcOutgoingQueueManager(_pubsub!.comms, gossipSubIDv11);
    } else {
      // This case should ideally not happen if PubSub construction is correct
      throw StateError('GossipSubRouter.attach: PubSub instance is null, cannot initialize RpcOutgoingQueueManager.');
    }
    _log.fine('GossipSubRouter attached to PubSub and RpcQueueManager initialized.');
  }

  @override
  Future<void> detach() async {
    _rpcQueueManager.clearAll();
    _pubsub = null;
    _log.fine('GossipSubRouter detached.');
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    _log.fine('GossipSubRouter: Peer added - ${peerId.toBase58()} on $protocolId');
    _pubsub?.addPeer(peerId, protocolId); // Notify PubSub core to manage scores
    final addPeerTrace = trace_pb.TraceEvent_AddPeer()
      ..peerID = peerId.toBytes()
      ..proto = protocolId;
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.ADD_PEER
      ..peerID = peerId.toBytes()
      ..addPeer = addPeerTrace
    );
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    _log.fine('GossipSubRouter: Peer removed - ${peerId.toBase58()}');
    _pubsub?.removePeer(peerId); // Notify PubSub core to manage scores
    final removePeerTrace = trace_pb.TraceEvent_RemovePeer()
      ..peerID = peerId.toBytes();
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.REMOVE_PEER
      ..peerID = peerId.toBytes()
      ..removePeer = removePeerTrace
    );
    mesh.forEach((topic, peers) => peers.remove(peerId));
    fanout.forEach((topic, peers) => peers.remove(peerId));
    _rpcQueueManager.peerDisconnected(peerId);
    
    // Unprotect peer since it's no longer in any mesh
    _pubsub?.host?.connManager.unprotect(peerId, 'gossipsub-mesh');
    _log.fine('GossipSubRouter: Unprotected removed peer $peerId');
  }

  @override
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc) async {
    final Set<String> acceptedMessageIds = {};
    _log.fine('GossipSubRouter: Handling RPC from ${peerId.toBase58()} for ${rpc.toShortString()}');
    final recvRpcTrace = trace_pb.TraceEvent_RecvRPC()
      ..receivedFrom = peerId.toBytes();
      // ..meta = ... ; // TODO: Populate meta if needed
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.RECV_RPC // Assuming RECV_RPC enum constant
      ..peerID = peerId.toBytes()
      ..recvRPC = recvRpcTrace
    );

    // Messages: drop duplicates first, then validate the new ones. Validation
    // can be async, so the messages of this RPC are validated concurrently,
    // and the subscriptions and control messages below are handled while
    // validation runs.
    final List<Future<String?>> pendingMessages = [];
    if (rpc.publish.isNotEmpty) {
      // Use the messageIdFn from pubsub, falling back to default if pubsub or its fn is null
      final msgIdFn = _pubsub?.messageIdFn ?? defaultMessageIdFn;
      for (final msgProto in rpc.publish) {
        final msgIdStr = msgIdFn(msgProto);

        if (_isSeen(msgIdStr)) {
          _handleDuplicate(peerId, msgProto, msgIdStr);
          continue;
        }
        // Mark the message as seen before validation, whatever the result,
        // so that its duplicates are not validated again.
        _seenMessages.add(msgIdStr);
        pendingMessages.add(_validateAndForward(peerId, msgProto, msgIdStr));
      }
    }

    if (rpc.subscriptions.isNotEmpty) {
      for (final subOpt in rpc.subscriptions) {
        final topicId = subOpt.topicid;
        if (subOpt.subscribe) {
          _log.fine('GossipSubRouter: Received SUBSCRIBE from $peerId for topic $topicId');
          // Track peer's subscription and add to mesh if we also subscribe to this topic
          _peerTopics.putIfAbsent(peerId, () => <String>{}).add(topicId);
          if (mesh.containsKey(topicId)) {
            mesh[topicId]!.add(peerId);
          }
        } else {
          _log.fine('GossipSubRouter: Received UNSUBSCRIBE from $peerId for topic $topicId');
          _peerTopics[peerId]?.remove(topicId);
          mesh[topicId]?.remove(peerId);
        }
      }
    }

    if (rpc.hasControl()) {
      final control = rpc.control;
      if (control.ihave.isNotEmpty) {
        _log.fine('GossipSubRouter: Received IHAVE from $peerId with ${control.ihave.length} entries.');
        final List<String> wantedMessageIds = [];
        for (final ihaveEntry in control.ihave) {
          for (final msgId in ihaveEntry.messageIDs) {
            if (!_isSeen(msgId)) {
              wantedMessageIds.add(msgId);
            }
          }
        }
        if (wantedMessageIds.isNotEmpty) {
          _log.fine('GossipSubRouter: Requesting ${wantedMessageIds.length} messages via IWANT from $peerId.');
          final iwantControl = pb.ControlIWant()..messageIDs.addAll(wantedMessageIds);
          final controlMsgToSend = pb.ControlMessage()..iwant.add(iwantControl);
          final rpcToSend = pb.RPC()..control = controlMsgToSend;
          
          final controlMeta = trace_pb.TraceEvent_ControlMeta();
          controlMsgToSend.ihave.forEach((ihave) {
            controlMeta.ihave.add(trace_pb.TraceEvent_ControlIHaveMeta()
              ..topic = ihave.topicID
              ..messageIDs.addAll(ihave.messageIDs.map((id) => id.codeUnits)));
          });
          // Similarly for iwant, graft, prune if they were part of controlMsgToSend
          final rpcMeta = trace_pb.TraceEvent_RPCMeta()..control = controlMeta;
          final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
            ..sendTo = peerId.toBytes()
            ..meta = rpcMeta;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.SEND_RPC 
            ..peerID = peerId.toBytes()
            ..sendRPC = sendRpcTrace
          );
          _rpcQueueManager.sendRpc(peerId, rpcToSend, protocolId: gossipSubIDv11);
        } else {
          _log.fine('GossipSubRouter: No new messages wanted from IHAVE by $peerId.');
        }
      }

      if (control.iwant.isNotEmpty) {
        _log.fine('GossipSubRouter: Received IWANT from $peerId with ${control.iwant.length} entries.');
        final List<pb.Message> messagesToSend = [];
        for (final iwantEntry in control.iwant) {
          for (final msgId in iwantEntry.messageIDs) {
            final msg = _mcache.getMessage(msgId);
            if (msg != null) {
              messagesToSend.add(msg);
            } else {
              _log.fine('GossipSubRouter: Peer $peerId wanted message $msgId which we do not have.');
            }
          }
        }
        if (messagesToSend.isNotEmpty) {
          _log.fine('GossipSubRouter: Sending ${messagesToSend.length} messages to $peerId in response to IWANT.');
          final rpcToSend = pb.RPC()..publish.addAll(messagesToSend);

          final rpcMeta = trace_pb.TraceEvent_RPCMeta();
          for (final msg in messagesToSend) {
            rpcMeta.messages.add(trace_pb.TraceEvent_MessageMeta()
              ..messageID = defaultMessageIdFn(msg).codeUnits
              ..topic = msg.topic);
          }
          final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
            ..sendTo = peerId.toBytes()
            ..meta = rpcMeta;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.SEND_RPC 
            ..peerID = peerId.toBytes()
            ..sendRPC = sendRpcTrace
          );
          _rpcQueueManager.sendRpc(peerId, rpcToSend, protocolId: gossipSubIDv11);
        }
      }

      if (control.graft.isNotEmpty) {
        for (final graft_msg in control.graft) {
          final topicId = graft_msg.topicID;
          _log.fine('GossipSubRouter: Received GRAFT from $peerId for topic $topicId.');
          final graftTrace = trace_pb.TraceEvent_Graft()
            ..peerID = peerId.toBytes()
            ..topic = topicId;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.GRAFT
            ..peerID = peerId.toBytes()
            ..graft = graftTrace
          );
          mesh.putIfAbsent(topicId, () => <PeerId>{});
          mesh[topicId]!.add(peerId);
          
          // Protect mesh peer connection to prevent premature disconnection
          _pubsub?.host?.connManager.protect(peerId, 'gossipsub-mesh');
          _log.fine('GossipSubRouter: Protected mesh peer $peerId for topic $topicId');
        }
      }
      if (control.prune.isNotEmpty) {
        for (final prune_msg in control.prune) {
          final topicId = prune_msg.topicID;
          _log.fine('GossipSubRouter: Received PRUNE from $peerId for topic $topicId.');
          final pruneTrace = trace_pb.TraceEvent_Prune()
            ..peerID = peerId.toBytes()
            ..topic = topicId;
           _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.PRUNE
            ..peerID = peerId.toBytes()
            ..prune = pruneTrace
          );
          mesh[topicId]?.remove(peerId);
          
          // Unprotect peer if not in any other mesh
          if (!_isPeerInAnyMesh(peerId)) {
            _pubsub?.host?.connManager.unprotect(peerId, 'gossipsub-mesh');
            _log.fine('GossipSubRouter: Unprotected peer $peerId (not in any mesh)');
          }
        }
      }
      if (control.idontwant.isNotEmpty) {
        _log.fine('GossipSubRouter: Received IDONTWANT from $peerId.');
      }
    }

    if (pendingMessages.isNotEmpty) {
      for (final acceptedId in await Future.wait(pendingMessages)) {
        if (acceptedId != null) acceptedMessageIds.add(acceptedId);
      }
    }
    return acceptedMessageIds;
  }

  /// Handles a message that was seen before: traces it as a duplicate and,
  /// if the first copy was rejected, penalises [peerId] as go-libp2p-pubsub
  /// does.
  void _handleDuplicate(PeerId peerId, pb.Message msgProto, String msgIdStr) {
    _log.fine('GossipSubRouter: Received duplicate message $msgIdStr from $peerId. Ignoring.');
    final duplicateMsgTrace = trace_pb.TraceEvent_DuplicateMessage()
      ..messageID = msgIdStr.codeUnits
      ..receivedFrom = peerId.toBytes()
      ..topic = msgProto.topic;
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE
      ..peerID = peerId.toBytes()
      ..duplicateMessage = duplicateMsgTrace
    );
    if (_rejectedMessages.contains(msgIdStr)) {
      _pubsub?.getPeerScoreObject(peerId)?.recordInvalidMessage(msgProto.topic);
    }
  }

  /// Validates a new message from [peerId]. If the message is accepted, puts
  /// it in the message cache, forwards it to the mesh peers of its topic and
  /// returns its ID; otherwise returns null. A rejected message penalises
  /// [peerId] (the peer that delivered it, not its author) on the topic.
  Future<String?> _validateAndForward(PeerId peerId, pb.Message msgProto, String msgIdStr) async {
    final pubsub = _pubsub;
    if (pubsub == null) {
      _log.warning('GossipSubRouter: PubSub not available for validation. Message $msgIdStr from $peerId dropped.');
      return null;
    }
    final msgIdBytes = msgIdStr.codeUnits;
    final topicId = msgProto.topic;

    ValidationResult validationResult;
    try {
      validationResult = await pubsub.validateMessage(
          PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId));
    } catch (e) {
      _log.warning('GossipSubRouter: Validation of message $msgIdStr from $peerId failed with an error: $e. Dropping.');
      return null;
    }
    if (_pubsub == null) return null; // Detached while the message was in validation.

    // PubSub traces REJECT_MESSAGE with the reason. Only reject costs the
    // sender score; ignore does not.
    if (validationResult == ValidationResult.reject) {
      _log.fine('GossipSubRouter: Message $msgIdStr from $peerId rejected. Dropping and penalising the sender.');
      _rejectedMessages.add(msgIdStr);
      pubsub.getPeerScoreObject(peerId)?.recordInvalidMessage(topicId);
      return null;
    }
    if (validationResult != ValidationResult.accept) {
      _log.fine('GossipSubRouter: Message $msgIdStr from $peerId ignored by validation. Dropping.');
      return null;
    }

    _log.fine('GossipSubRouter: Received new message $msgIdStr from $peerId to process/forward.');
    _mcache.put(msgProto);

    // Trace DELIVER_MESSAGE as the router has accepted it for processing/forwarding
    final deliverMsgTrace = trace_pb.TraceEvent_DeliverMessage()
      ..messageID = msgIdBytes
      ..receivedFrom = peerId.toBytes()
      ..topic = topicId;
    pubsub.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.DELIVER_MESSAGE
      ..peerID = peerId.toBytes() // Peer from which the message was received that is now being delivered/processed
      ..deliverMessage = deliverMsgTrace
    );

    // Forward the valid message to other mesh peers for the topic
    final meshPeersForTopic = mesh[topicId];
    if (meshPeersForTopic != null && meshPeersForTopic.isNotEmpty) {
      final rpcToSend = pb.RPC()..publish.add(msgProto);
      int forwardedCount = 0;
      for (final meshPeerId in List<PeerId>.from(meshPeersForTopic)) {
        if (meshPeerId == peerId) continue; // Don't send back to the source

        _log.fine('GossipSubRouter: Forwarding message $msgIdStr on topic $topicId to mesh peer ${meshPeerId.toBase58()}');
        final messageMeta = trace_pb.TraceEvent_MessageMeta()
          ..messageID = msgIdBytes
          ..topic = topicId;
        final rpcMeta = trace_pb.TraceEvent_RPCMeta()..messages.add(messageMeta);
        final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
          ..sendTo = meshPeerId.toBytes()
          ..meta = rpcMeta;
        pubsub.tracer.trace(trace_pb.TraceEvent()
          ..type = trace_pb.TraceEvent_Type.SEND_RPC
          ..peerID = meshPeerId.toBytes()
          ..sendRPC = sendRpcTrace
        );
        _rpcQueueManager.sendRpc(meshPeerId, rpcToSend, protocolId: gossipSubIDv11);
        forwardedCount++;
      }
      if (forwardedCount > 0) {
        _log.fine('GossipSubRouter: Forwarded message $msgIdStr to $forwardedCount mesh peers for topic $topicId.');
      }
    }
    // PubSub delivers the message to local subscribers after handleRpc
    // returns, for the IDs that this method accepted.
    return msgIdStr;
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final topicId = message.topic;
    _log.fine('GossipSubRouter: Publishing message for topic $topicId from ${message.from.toBase58()}');

    if (_pubsub == null || _pubsub?.comms == null) {
      _log.warning('GossipSubRouter: PubSub or comms not attached. Cannot publish.');
      return;
    }

    final rpcToSend = pb.RPC()..publish.add(message.rpcMessage);
    _mcache.put(message.rpcMessage);
    _seenMessages.add(defaultMessageIdFn(message.rpcMessage));

    final Set<PeerId> peersToPublish = {};
    final meshPeers = mesh[topicId];
    if (meshPeers != null) {
      peersToPublish.addAll(meshPeers);
    }
    final fanoutPeers = fanout[topicId];
    if (fanoutPeers != null) {
      peersToPublish.addAll(fanoutPeers);
      fanoutLastPublished[topicId] = DateTime.now();
    }
    
    // GossipSub v1.1 spec: for publish-only topics (not in mesh), build fanout
    // from peers known to be subscribed to this topic via _peerTopics.
    if (peersToPublish.isEmpty) {
      final newFanout = <PeerId>{};
      for (final entry in _peerTopics.entries) {
        if (entry.value.contains(topicId)) {
          newFanout.add(entry.key);
          if (newFanout.length >= params.D) break;
        }
      }
      if (newFanout.isNotEmpty) {
        fanout[topicId] = newFanout;
        fanoutLastPublished[topicId] = DateTime.now();
        peersToPublish.addAll(newFanout);
        _log.fine('GossipSubRouter: Built fanout for publish-only topic $topicId with ${newFanout.length} peers from _peerTopics.');
      } else {
        _log.fine('GossipSubRouter: No peers in mesh, fanout, or _peerTopics for topic $topicId to publish to.');
      }
    }

    for (final peerId in peersToPublish) {
      if (peerId == message.receivedFrom) {
        continue;
      }
      _log.fine('GossipSubRouter: Sending message on topic $topicId to peer ${peerId.toBase58()}');
      try {
        // Note: The actual PUBLISH_MESSAGE trace is done in PubSub.publish
        // Here we trace the SEND_RPC event for this specific peer.
        final messageMeta = trace_pb.TraceEvent_MessageMeta()
          ..messageID = defaultMessageIdFn(message.rpcMessage).codeUnits
          ..topic = topicId;
        final rpcMeta = trace_pb.TraceEvent_RPCMeta()..messages.add(messageMeta);
        final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
          ..sendTo = peerId.toBytes()
          ..meta = rpcMeta;
        _pubsub?.tracer.trace(trace_pb.TraceEvent()
          ..type = trace_pb.TraceEvent_Type.SEND_RPC 
          ..peerID = peerId.toBytes() // The peer we are sending to
          ..sendRPC = sendRpcTrace
        );
        _rpcQueueManager.sendRpc(peerId, rpcToSend, protocolId: gossipSubIDv11);
      } catch (e) {
        _log.fine('GossipSubRouter: Error enqueuing message to peer ${peerId.toBase58()}: $e');
      }
    }

    // IHAVE gossip: Announce the message to other good-scoring peers not in the mesh.
    final List<PeerId> ihavePeers = [];
    final allConnectedPeers = _pubsub?.host.network.peers.toList() ?? [];
    
    for (final peerId in allConnectedPeers) {
      if (peerId == _pubsub?.host.id) continue; // Don't send to self
      if (peerId == message.receivedFrom) continue; // Don't send back to origin
      if (peersToPublish.contains(peerId)) continue; // Already sent full message

      // Check score
      final score = _pubsub?.getPeerScore(peerId) ?? -double.infinity;
      if (score < params.DScore) continue; // Skip low-scoring peers

      ihavePeers.add(peerId);
    }

      if (ihavePeers.isNotEmpty) {
        ihavePeers.shuffle();
        final selectedIhavePeers = ihavePeers.take(min(params.DLazy, ihavePeers.length));

        if (selectedIhavePeers.isNotEmpty) {
          final msgIdStr = defaultMessageIdFn(message.rpcMessage);
          final ihaveControl = pb.ControlIHave() 
            ..topicID = topicId
            ..messageIDs.add(msgIdStr);
          final controlMsgToSend = pb.ControlMessage()..ihave.add(ihaveControl);
          final ihaveRpc = pb.RPC()..control = controlMsgToSend;

        for (final peerId in selectedIhavePeers) {
          _log.fine('GossipSubRouter: Sending IHAVE for message $msgIdStr on topic $topicId to peer ${peerId.toBase58()}');
          final controlMeta = trace_pb.TraceEvent_ControlMeta();
          controlMsgToSend.ihave.forEach((ihave) { // Assuming controlMsgToSend is pb.ControlMessage
            controlMeta.ihave.add(trace_pb.TraceEvent_ControlIHaveMeta()
              ..topic = ihave.topicID
              ..messageIDs.addAll(ihave.messageIDs.map((id) => id.codeUnits)));
          });
          final rpcMeta = trace_pb.TraceEvent_RPCMeta()..control = controlMeta;
          final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
            ..sendTo = peerId.toBytes()
            ..meta = rpcMeta;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.SEND_RPC
            ..peerID = peerId.toBytes()
            ..sendRPC = sendRpcTrace
          );
          _rpcQueueManager.sendRpc(peerId, ihaveRpc, protocolId: gossipSubIDv11);
        }
      }
    }
  }

  @override
  Future<void> join(Topic topic) async {
    final topicId = topic.name;
    _log.fine('GossipSubRouter: Joining topic $topicId');

    // Removed Diagnostic prints
    // if (_pubsub == null) {
    //   print('[DEBUG] GossipSubRouter.join: _pubsub is null!');
    // } else if (_pubsub!.host == null) { // Should not happen if _pubsub is not null and Host is non-nullable field
    //   print('[DEBUG] GossipSubRouter.join: _pubsub.host is null!');
    // } else {
    //   final peers = _pubsub!.host.network.peers;
    //   print('[DEBUG] GossipSubRouter.join: For host ${_pubsub!.host.id.toBase58()}, network.peers = ${peers.map((p) => p.toBase58()).toList()}');
    // }

    final joinTrace = trace_pb.TraceEvent_Join()..topic = topicId;
    // Ensure _pubsub and _pubsub.host and _pubsub.host.id are not null before calling toBytes
    final localPeerIdBytes = _pubsub?.host?.id?.toBytes() ?? Uint8List(0); // Provide a default if any part is null

    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.JOIN
      ..peerID = localPeerIdBytes 
      ..join = joinTrace
    );

    final meshPeers = mesh.putIfAbsent(topicId, () => <PeerId>{});

    // As in go-libp2p-pubsub: build the mesh from the fanout peers of the
    // topic first, then from the other peers subscribed to it, and GRAFT
    // them, up to D peers. The fanout of the topic is no longer needed.
    final candidates = <PeerId>[
      ...(fanout.remove(topicId)?.toList() ?? <PeerId>[])..shuffle(),
      ..._topicPeers(topicId).toList()..shuffle(),
    ];
    fanoutLastPublished.remove(topicId);

    final connected = _pubsub?.host.network.peers.toSet() ?? <PeerId>{};
    for (final peerId in candidates) {
      if (meshPeers.length >= params.D) break;
      if (peerId == _pubsub?.host.id) continue;
      if (meshPeers.contains(peerId)) continue;
      if (!connected.contains(peerId)) continue;
      final score = _pubsub?.getPeerScore(peerId) ?? 0.0;
      if (score < params.DScore) continue;

      _log.fine('GossipSubRouter: join: Sending GRAFT to ${peerId.toBase58()} for topic $topicId.');
      _sendGraft(peerId, topicId);
      meshPeers.add(peerId);
      _pubsub?.host.connManager.protect(peerId, 'gossipsub-mesh');
    }
  }

  @override
  Future<void> leave(Topic topic) async {
    final topicId = topic.name;
    _log.fine('GossipSubRouter: Leaving topic $topicId');
    final leaveTrace = trace_pb.TraceEvent_Leave()..topic = topicId;
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.LEAVE 
      ..peerID = _pubsub?.host.id.toBytes() ?? <int>[] // Local peer ID for JOIN/LEAVE events
      ..leave = leaveTrace
    );

    final meshPeers = mesh.remove(topicId) ?? <PeerId>{};
    for (final peerToPrune in meshPeers) {
      _log.fine('GossipSubRouter: leave: Sending PRUNE to ${peerToPrune.toBase58()} for topic $topicId.');
      _sendPrune(peerToPrune, topicId, backoff: params.unsubscribeBackoff);
      if (!_isPeerInAnyMesh(peerToPrune)) {
        _pubsub?.host.connManager.unprotect(peerToPrune, 'gossipsub-mesh');
      }
    }

    fanout.remove(topicId);
    fanoutLastPublished.remove(topicId);
  }

  @override
  Future<void> start() async {
    _mcache.start();
    _heartbeatTimer?.cancel();
    _heartbeatTicks = 0;
    // As in go-libp2p-pubsub: the first heartbeat after the initial delay,
    // then one every heartbeat interval.
    _heartbeatTimer = Timer(params.heartbeatInitialDelay, () {
      _heartbeatTimer = Timer.periodic(params.heartbeatInterval, (_) => _heartbeat());
      _heartbeat();
    });
    _log.fine('GossipSubRouter started, mcache and heartbeat timers initiated.');
  }

  @override
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _mcache.dispose();
    _seenMessages.clear();
    _rejectedMessages.clear();
    _log.fine('GossipSubRouter stopped, mcache and heartbeat timers stopped.');
  }

  /// Helper method to determine if a peer is "new" and should be treated with permissive grafting criteria
  bool _isNewPeer(dynamic peerScore) {
    // Consider a peer "new" if:
    // 1. They have minimal interaction history
    // 2. They've been connected for a short time
    // 3. Their score is close to the initial value
    
    final now = DateTime.now();
    
    // For now, use a simple heuristic based on score proximity to initial/neutral value
    // In a full implementation, this could check:
    // - Time since first seen
    // - Number of messages exchanged
    // - Connection duration
    final score = peerScore.score as double;
    
    // Consider peers with scores close to neutral as "new"
    // This covers newly connected peers who haven't had time to build reputation
    if (score > -2.0 && score < 2.0) {
      return true;
    }
    
    return false;
  }

  /// Check if a peer is in any mesh (across all topics)
  bool _isPeerInAnyMesh(PeerId peerId) {
    for (final meshPeers in mesh.values) {
      if (meshPeers.contains(peerId)) {
        return true;
      }
    }
    return false;
  }

  /// The peers known to be subscribed to [topicId].
  Iterable<PeerId> _topicPeers(String topicId) => _peerTopics.entries
      .where((entry) => entry.value.contains(topicId))
      .map((entry) => entry.key);

  /// The connected peers known to be subscribed to [topicId]: the
  /// candidates to GRAFT for the topic.
  List<PeerId> _connectedTopicPeers(String topicId) {
    final connected = _pubsub?.host.network.peers.toSet() ?? <PeerId>{};
    return _topicPeers(topicId).where(connected.contains).toList();
  }

  /// Sends a GRAFT for [topicId] to [peerId] and traces the RPC.
  void _sendGraft(PeerId peerId, String topicId) {
    final controlMsg = pb.ControlMessage()..graft.add(pb.ControlGraft()..topicID = topicId);
    final controlMeta = trace_pb.TraceEvent_ControlMeta()
      ..graft.add(trace_pb.TraceEvent_ControlGraftMeta()..topic = topicId);
    _sendControl(peerId, controlMsg, controlMeta);
  }

  /// Sends a PRUNE for [topicId] to [peerId], with the given PX peers and
  /// backoff, traces the RPC and traces the PRUNE.
  void _sendPrune(PeerId peerId, String topicId,
      {List<pb.PeerInfo> pxPeers = const [], Duration? backoff}) {
    final pruneCtrl = pb.ControlPrune()
      ..topicID = topicId
      ..peers.addAll(pxPeers);
    if (backoff != null) {
      pruneCtrl.backoff = Int64(backoff.inSeconds);
    }
    final controlMsg = pb.ControlMessage()..prune.add(pruneCtrl);
    final pruneMeta = trace_pb.TraceEvent_ControlPruneMeta()..topic = topicId;
    for (final pxPeer in pxPeers) {
      pruneMeta.peers.add(pxPeer.peerID);
    }
    final controlMeta = trace_pb.TraceEvent_ControlMeta()..prune.add(pruneMeta);
    _sendControl(peerId, controlMsg, controlMeta);

    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.PRUNE
      ..peerID = peerId.toBytes()
      ..prune = (trace_pb.TraceEvent_Prune()
        ..peerID = peerId.toBytes()
        ..topic = topicId)
    );
  }

  void _sendControl(PeerId peerId, pb.ControlMessage controlMsg, trace_pb.TraceEvent_ControlMeta controlMeta) {
    final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
      ..sendTo = peerId.toBytes()
      ..meta = (trace_pb.TraceEvent_RPCMeta()..control = controlMeta);
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.SEND_RPC
      ..peerID = peerId.toBytes()
      ..sendRPC = sendRpcTrace
    );
    _rpcQueueManager.sendRpc(peerId, pb.RPC()..control = controlMsg, protocolId: gossipSubIDv11);
  }

  void _heartbeat() {
    _log.fine('GossipSubRouter: Heartbeat tick');
    final now = DateTime.now();
    _heartbeatTicks++;

    // Refresh scores for all known peers
    _pubsub?.refreshScores();

    // Opportunistic Grafting, once every opportunisticGraftTicks heartbeats.
    // Iterate over all known topics we are subscribed to
    final opportunisticGraft = _heartbeatTicks % params.opportunisticGraftTicks == 0;
    _pubsub?.getTopics().forEach((topicId) {
      mesh.putIfAbsent(topicId, () => <PeerId>{}); // Ensure mesh entry exists
      if (!opportunisticGraft) return;
      final currentMeshPeers = mesh[topicId]!;
      
      if (currentMeshPeers.length >= params.DHigh) {
        return; // Mesh is full or overfull, no room for opportunistic grafts
      }

      final potentialPeers = _connectedTopicPeers(topicId);
      potentialPeers.shuffle(); // Randomize to give different peers a chance over time

      for (final peerId in potentialPeers) {
        if (peerId == _pubsub?.host.id) continue;
        if (currentMeshPeers.contains(peerId)) continue; // Already in mesh

        final score = _pubsub?.getPeerScore(peerId) ?? -double.infinity;
        if (score >= params.opportunisticGraftScoreThreshold) {
          if (currentMeshPeers.length < params.DHigh) { // Double check before grafting
            _log.fine('Heartbeat: Opportunistically GRAFTing ${peerId.toBase58()} to topic $topicId (score: $score)');
            _sendGraft(peerId, topicId);
            mesh[topicId]!.add(peerId); // Optimistically add
            _pubsub?.host.connManager.protect(peerId, 'gossipsub-mesh');
            // Break if we've reached DHigh to avoid over-grafting in one heartbeat
            if (mesh[topicId]!.length >= params.DHigh) break; 
          }
        }
      }
    });


    // Mesh Maintenance (Deficiency/Surplus)
    mesh.forEach((topicId, currentMeshPeers) {
      final currentMeshSize = currentMeshPeers.length;
      if (currentMeshSize < params.DLow) {
        final needed = params.D - currentMeshSize;
        if (needed <= 0) return;

        _log.fine('Heartbeat: Topic $topicId mesh too small ($currentMeshSize < ${params.DLow}). Need $needed more peers. Attempting to find and GRAFT.');

        // Get potential peers: the connected peers subscribed to the topic.
        var potentialPeers = _connectedTopicPeers(topicId);
        
        // Filter out self, peers already in mesh, using permissive scoring for new peers.
        potentialPeers = potentialPeers.where((peerId) {
          if (peerId == _pubsub?.host.id) return false; // Don't graft self
          if (currentMeshPeers.contains(peerId)) return false; // Already in mesh

          final peerScoreObj = _pubsub?.getPeerScoreObject(peerId);
          if (peerScoreObj == null) {
            // No score object exists - this is a new peer, allow it
            _log.fine('Heartbeat: Allowing new peer ${peerId.toBase58()} for topic $topicId (no score history)');
            return true;
          }
          
          final score = peerScoreObj.score;
          
          // Check if this is a "new" peer (recently connected, minimal interaction)
          final isNewPeer = _isNewPeer(peerScoreObj);
          if (isNewPeer) {
            // For new peers, use a more permissive threshold
            final permissiveThreshold = params.DScore - 5.0;
            if (score >= permissiveThreshold) {
              _log.fine('Heartbeat: Allowing new peer ${peerId.toBase58()} for topic $topicId (score: $score, permissive threshold: $permissiveThreshold)');
              return true;
            }
          }
          
          // For established peers, use normal threshold
          if (score >= params.DScore) {
            return true;
          }
          
          _log.fine('Heartbeat: Excluding peer ${peerId.toBase58()} for topic $topicId (score: $score, threshold: ${params.DScore}, isNew: $isNewPeer)');
          return false;
        }).toList();

        if (potentialPeers.isEmpty) {
          _log.fine('Heartbeat: No suitable peers found with normal criteria for topic $topicId.');
          
          // Fallback: Try with even more permissive criteria
          var fallbackPeers = _connectedTopicPeers(topicId);
          fallbackPeers = fallbackPeers.where((peerId) {
            if (peerId == _pubsub?.host.id) return false;
            if (currentMeshPeers.contains(peerId)) return false;
            
            // Only exclude peers with very bad scores (e.g., < -10.0)
            final score = _pubsub?.getPeerScore(peerId) ?? 0.0; // Default to 0 instead of -infinity
            return score >= -10.0;
          }).toList();
          
          if (fallbackPeers.isNotEmpty) {
            _log.fine('Heartbeat: Using fallback criteria, found ${fallbackPeers.length} peers for topic $topicId.');
            potentialPeers = fallbackPeers;
          } else {
            _log.fine('Heartbeat: No suitable peers found even with fallback criteria for topic $topicId.');
            return;
          }
        }

        potentialPeers.shuffle(); // Randomize selection

        final peersToGraft = potentialPeers.take(min(needed, potentialPeers.length)).toList();

        for (final peerToGraft in peersToGraft) {
          _log.fine('Heartbeat: Sending GRAFT to ${peerToGraft.toBase58()} for topic $topicId.');
          _sendGraft(peerToGraft, topicId);
          // Optimistically add to mesh, will be confirmed if peer accepts GRAFT (not handled here)
          // Or, wait for GRAFT ACK if that's part of the protocol (GossipSub v1.1 doesn't have GRAFT ACKs)
          // For now, we assume GRAFT implies an attempt to join, actual mesh state updates on receiving messages or PRUNE.
          // However, the spec implies we add them to our mesh when we send GRAFT.
          mesh[topicId]!.add(peerToGraft); 
          _pubsub?.host.connManager.protect(peerToGraft, 'gossipsub-mesh');
        }
      } else if (currentMeshSize > params.DHigh) {
        final excess = currentMeshSize - params.D; // Number of peers to prune to reach D
        _log.fine('Heartbeat: Topic $topicId mesh too large ($currentMeshSize > ${params.DHigh}). Need to prune $excess peers.');

        // Sort peers by score, lowest first. If scores are equal, order is not critical.
        // Peers with no score or lower scores are pruned first.
        List<PeerId> sortedMeshPeers = List<PeerId>.from(currentMeshPeers);
        sortedMeshPeers.sort((a, b) {
          final scoreA = _pubsub?.getPeerScore(a) ?? -double.infinity;
          final scoreB = _pubsub?.getPeerScore(b) ?? -double.infinity;
          return scoreA.compareTo(scoreB); // Ascending sort by score
        });

        final peersToPrune = sortedMeshPeers.take(excess).toList();

        for (final peerToPrune in peersToPrune) {
          _log.fine('Heartbeat: Sending PRUNE to ${peerToPrune.toBase58()} for topic $topicId.');

          // Add Peer Exchange (PX) information
          final List<pb.PeerInfo> pxPeers = []; // Corrected type to pb.PeerInfo
          // Select some other peers from the current mesh to suggest
          final otherMeshPeers = List<PeerId>.from(currentMeshPeers.where((p) => p != peerToPrune));
          otherMeshPeers.shuffle();
          final selectedPxPeers = otherMeshPeers.take(min(params.prunePeers, otherMeshPeers.length));
          
          for (final pxPeerId in selectedPxPeers) {
            // TODO: Add signed peer records if available and required by spec/implementation.
            // For now, just sending PeerID.
            pxPeers.add(pb.PeerInfo()..peerID = pxPeerId.toBytes()); // Corrected constructor to pb.PeerInfo
          }
          if (pxPeers.isNotEmpty) {
            _log.fine('Heartbeat: Adding ${pxPeers.length} PX peers to PRUNE for ${peerToPrune.toBase58()} on topic $topicId.');
          }

          // TODO: Add backoff logic for PRUNE as per spec (ControlPrune.backoff)
          _sendPrune(peerToPrune, topicId, pxPeers: pxPeers);
          
          // Remove from local mesh
          mesh[topicId]!.remove(peerToPrune);
          
          // Unprotect peer if not in any other mesh
          if (!_isPeerInAnyMesh(peerToPrune)) {
            _pubsub?.host?.connManager.unprotect(peerToPrune, 'gossipsub-mesh');
            _log.fine('Heartbeat: Unprotected pruned peer $peerToPrune (not in any mesh)');
          }
        }
      }
    });

    List<String> topicsToRemoveFromFanout = [];
    fanout.forEach((topicId, fanoutPeers) {
      final lastPub = fanoutLastPublished[topicId];
      if (lastPub == null || now.difference(lastPub) > params.fanoutTTL) {
        _log.fine('Heartbeat: Fanout TTL expired for topic $topicId. Removing from fanout.');
        topicsToRemoveFromFanout.add(topicId);
      } else if (fanoutPeers.length < params.D) {
        final needed = params.D - fanoutPeers.length;
        _log.fine('Heartbeat: Fanout for topic $topicId too small (${fanoutPeers.length} < ${params.D}). Need $needed more fanout peers.');

        var potentialFanoutPeers = _pubsub?.host.network.peers.toList() ?? [];
        potentialFanoutPeers = potentialFanoutPeers.where((peerId) {
          if (peerId == _pubsub?.host.id) return false;
          if (fanoutPeers.contains(peerId)) return false; // Already in fanout
          if (mesh[topicId]?.contains(peerId) ?? false) return false; // Already in mesh for this topic

          final score = _pubsub?.getPeerScore(peerId) ?? -double.infinity;
          return score >= params.DScore; // Ensure good score
        }).toList();

        if (potentialFanoutPeers.isEmpty) {
          _log.fine('Heartbeat: No suitable peers found to add to fanout for topic $topicId.');
        } else {
          potentialFanoutPeers.shuffle();
          final peersToAdd = potentialFanoutPeers.take(min(needed, potentialFanoutPeers.length)).toList();
          for (final peerToAdd in peersToAdd) {
            _log.fine('Heartbeat: Adding ${peerToAdd.toBase58()} to fanout for topic $topicId.');
            fanout[topicId]!.add(peerToAdd);
          }
        }
      }
    });
    for (final topicId in topicsToRemoveFromFanout) {
      fanout.remove(topicId);
      fanoutLastPublished.remove(topicId);
    }
  }
}

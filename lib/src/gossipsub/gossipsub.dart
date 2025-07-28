import 'dart:async';
import 'dart:math';
import 'dart:typed_data'; // Added explicit import for Uint8List

import 'package:dart_libp2p/core/peer/peer_id.dart';

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
import '../core/validation.dart'; // For ValidationResult

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
  });

  static GossipSubParams get defaultParams => GossipSubParams();
}

/// Implementation of the GossipSub_v1.1 routing protocol.
class GossipSubRouter implements Router {
  PubSub? _pubsub; // Reference to the PubSub instance
  late final GossipSubParams params;
  late final RpcOutgoingQueueManager _rpcQueueManager;
  late final MessageCache _mcache;

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

  // TODO: Add other GossipSub specific fields:
  // - Seen cache (for IHAVE messages / control message IDs)
  // - Peer scores
  Timer? _heartbeatTimer;
  // - Outbound RPC queues per peer
  // - etc.

  /// Returns true if the router has been started and the heartbeat is active.
  bool get isStarted => _heartbeatTimer != null;

  GossipSubRouter({GossipSubParams? params}) {
    this.params = params ?? GossipSubParams.defaultParams;
    _mcache = MessageCache(
        // TODO: Consider passing cache parameters from GossipSubParams
        );
  }

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
    print('GossipSubRouter attached to PubSub and RpcQueueManager initialized.');
  }

  @override
  Future<void> detach() async {
    _rpcQueueManager.clearAll();
    _pubsub = null;
    print('GossipSubRouter detached.');
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    print('GossipSubRouter: Peer added - ${peerId.toBase58()} on $protocolId');
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
    print('GossipSubRouter: Peer removed - ${peerId.toBase58()}');
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
  }

  @override
  Future<void> handleRpc(PeerId peerId, pb.RPC rpc) async {
    print('GossipSubRouter: Handling RPC from ${peerId.toBase58()} for ${rpc.toShortString()}');
    final recvRpcTrace = trace_pb.TraceEvent_RecvRPC()
      ..receivedFrom = peerId.toBytes();
      // ..meta = ... ; // TODO: Populate meta if needed
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.RECV_RPC // Assuming RECV_RPC enum constant
      ..peerID = peerId.toBytes()
      ..recvRPC = recvRpcTrace
    );

    if (rpc.publish.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        // Use the messageIdFn from pubsub, falling back to default if pubsub or its fn is null
        final msgIdFn = _pubsub?.messageIdFn ?? defaultMessageIdFn;
        final msgIdStr = msgIdFn(msgProto);
        final msgIdBytes = msgIdStr.codeUnits; // msgIdStr should not be null here

        // --- BEGIN INSERTED VALIDATION LOGIC ---
        final pubSubMessage = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
        final validationResult = _pubsub?.validateMessage(pubSubMessage);

        if (validationResult == null) { // Should not happen if pubsub is attached
            print('GossipSubRouter: PubSub not available for validation. Message $msgIdStr from $peerId dropped.');
            // Optionally trace an error or internal issue
            continue;
        }
        
        if (validationResult == ValidationResult.reject || validationResult == ValidationResult.ignore) {
          print('GossipSubRouter: Message $msgIdStr from $peerId failed validation ($validationResult). Dropping.');
          final rejectMsgTrace = trace_pb.TraceEvent_RejectMessage()
            ..messageID = msgIdBytes
            ..receivedFrom = peerId.toBytes()
            ..topic = msgProto.topic
            ..reason = validationResult.name; // Use enum .name for string representation
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.REJECT_MESSAGE
            ..peerID = peerId.toBytes()
            ..rejectMessage = rejectMsgTrace
          );
          continue; // Skip further processing for this message
        }
        // --- END INSERTED VALIDATION LOGIC ---

        // If validation passed (accept), then proceed with duplicate check and processing
        if (_mcache.seen(msgIdStr)) {
          print('GossipSubRouter: Received duplicate message $msgIdStr from $peerId. Ignoring.');
          final duplicateMsgTrace = trace_pb.TraceEvent_DuplicateMessage()
            ..messageID = msgIdBytes
            ..receivedFrom = peerId.toBytes()
            ..topic = msgProto.topic;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE
            ..peerID = peerId.toBytes()
            ..duplicateMessage = duplicateMsgTrace
          );
          continue;
        }
        print('GossipSubRouter: Received new message $msgIdStr from $peerId to process/forward.');
        _mcache.put(msgProto);

        // Trace DELIVER_MESSAGE as the router has accepted it for processing/forwarding
        final deliverMsgTrace = trace_pb.TraceEvent_DeliverMessage()
          ..messageID = msgIdBytes
          ..receivedFrom = peerId.toBytes()
          ..topic = msgProto.topic;
        _pubsub?.tracer.trace(trace_pb.TraceEvent()
          ..type = trace_pb.TraceEvent_Type.DELIVER_MESSAGE
          ..peerID = peerId.toBytes() // Peer from which the message was received that is now being delivered/processed
          ..deliverMessage = deliverMsgTrace
        );

        // Forward the valid message to other mesh peers for the topic
        final topicId = msgProto.topic;
        final meshPeersForTopic = mesh[topicId];
        if (meshPeersForTopic != null && meshPeersForTopic.isNotEmpty) {
          final rpcToSend = pb.RPC()..publish.add(msgProto);
          int forwardedCount = 0;
          for (final meshPeerId in meshPeersForTopic) {
            if (meshPeerId == peerId) continue; // Don't send back to the source

            // TODO: Check if this peer has already seen the message (e.g. via mcache or a per-peer seen cache)
            // For now, assume mcache check at their end is sufficient, or rely on not sending back to source.
            
            print('GossipSubRouter: Forwarding message $msgIdStr on topic $topicId to mesh peer ${meshPeerId.toBase58()}');
            final messageMeta = trace_pb.TraceEvent_MessageMeta()
              ..messageID = msgIdBytes
              ..topic = topicId;
            final rpcMeta = trace_pb.TraceEvent_RPCMeta()..messages.add(messageMeta);
            final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
              ..sendTo = meshPeerId.toBytes()
              ..meta = rpcMeta;
            _pubsub?.tracer.trace(trace_pb.TraceEvent()
              ..type = trace_pb.TraceEvent_Type.SEND_RPC
              ..peerID = meshPeerId.toBytes()
              ..sendRPC = sendRpcTrace
            );
            _rpcQueueManager.sendRpc(meshPeerId, rpcToSend, protocolId: gossipSubIDv11);
            forwardedCount++;
          }
          if (forwardedCount > 0) {
            print('GossipSubRouter: Forwarded message $msgIdStr to $forwardedCount mesh peers for topic $topicId.');
          }
        }
        
        // Also deliver to local subscribers if PubSub is attached
        // This is typically handled by PubSub core after router processes it.
        // The router's job is to propagate. PubSub itself will call deliverReceivedMessage.
        // Let's assume PubSub will call its deliverReceivedMessage method after handleRpc completes
        // and the message is validated and processed by the router.
        // For now, we ensure the message is in mcache. The PubSub layer would then pick it up.
        // If direct delivery from router is needed:
        // final pubSubMessage = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
        // _pubsub?.deliverReceivedMessage(pubSubMessage);

      }
    }

    if (rpc.subscriptions.isNotEmpty) {
      for (final subOpt in rpc.subscriptions) {
        if (subOpt.subscribe) {
          print('GossipSubRouter: Received SUBSCRIBE from $peerId for topic ${subOpt.topicid}');
        } else {
          print('GossipSubRouter: Received UNSUBSCRIBE from $peerId for topic ${subOpt.topicid}');
        }
      }
    }

    if (rpc.hasControl()) {
      final control = rpc.control;
      if (control.ihave.isNotEmpty) {
        print('GossipSubRouter: Received IHAVE from $peerId with ${control.ihave.length} entries.');
        final List<String> wantedMessageIds = [];
        for (final ihaveEntry in control.ihave) {
          for (final msgId in ihaveEntry.messageIDs) {
            if (!_mcache.seen(msgId)) {
              wantedMessageIds.add(msgId);
            }
          }
        }
        if (wantedMessageIds.isNotEmpty) {
          print('GossipSubRouter: Requesting ${wantedMessageIds.length} messages via IWANT from $peerId.');
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
          print('GossipSubRouter: No new messages wanted from IHAVE by $peerId.');
        }
      }

      if (control.iwant.isNotEmpty) {
        print('GossipSubRouter: Received IWANT from $peerId with ${control.iwant.length} entries.');
        final List<pb.Message> messagesToSend = [];
        for (final iwantEntry in control.iwant) {
          for (final msgId in iwantEntry.messageIDs) {
            final msg = _mcache.getMessage(msgId);
            if (msg != null) {
              messagesToSend.add(msg);
            } else {
              print('GossipSubRouter: Peer $peerId wanted message $msgId which we do not have.');
            }
          }
        }
        if (messagesToSend.isNotEmpty) {
          print('GossipSubRouter: Sending ${messagesToSend.length} messages to $peerId in response to IWANT.');
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
          print('GossipSubRouter: Received GRAFT from $peerId for topic $topicId.');
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
        }
      }
      if (control.prune.isNotEmpty) {
        for (final prune_msg in control.prune) {
          final topicId = prune_msg.topicID;
          print('GossipSubRouter: Received PRUNE from $peerId for topic $topicId.');
          final pruneTrace = trace_pb.TraceEvent_Prune()
            ..peerID = peerId.toBytes()
            ..topic = topicId;
           _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.PRUNE
            ..peerID = peerId.toBytes()
            ..prune = pruneTrace
          );
          mesh[topicId]?.remove(peerId);
        }
      }
      if (control.idontwant.isNotEmpty) {
        print('GossipSubRouter: Received IDONTWANT from $peerId.');
      }
    }
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final topicId = message.topic;
    print('GossipSubRouter: Publishing message for topic $topicId from ${message.from.toBase58()}');

    if (_pubsub == null || _pubsub?.comms == null) {
      print('GossipSubRouter: PubSub or comms not attached. Cannot publish.');
      return;
    }

    final rpcToSend = pb.RPC()..publish.add(message.rpcMessage);
    _mcache.put(message.rpcMessage);

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
    
    if (peersToPublish.isEmpty) {
      print('GossipSubRouter: No peers in mesh or fanout for topic $topicId to publish to.');
    }

    for (final peerId in peersToPublish) {
      if (peerId == message.receivedFrom) {
        continue;
      }
      print('GossipSubRouter: Sending message on topic $topicId to peer ${peerId.toBase58()}');
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
        print('GossipSubRouter: Error enqueuing message to peer ${peerId.toBase58()}: $e');
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
          print('GossipSubRouter: Sending IHAVE for message $msgIdStr on topic $topicId to peer ${peerId.toBase58()}');
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
    print('GossipSubRouter: Joining topic $topicId');

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

    mesh.putIfAbsent(topicId, () => <PeerId>{});
    fanout.putIfAbsent(topicId, () => <PeerId>{});

    // Removed DEBUG: Eagerly add all other known peers to the mesh for this topic
    // // This is for testing message propagation directly, not correct GossipSub behavior.
    // if (_pubsub != null && _pubsub!.host != null) { // Check _pubsub.host explicitly
    //   final currentPeersInMesh = mesh[topicId]!; // Assumes topicId is always in mesh after putIfAbsent
    //   final networkPeers = _pubsub!.host.network.peers;
    //   if (networkPeers.isNotEmpty) {
    //     networkPeers.forEach((peerId) {
    //       if (peerId != _pubsub!.host.id && !currentPeersInMesh.contains(peerId)) {
    //         print('[DEBUG] GossipSubRouter.join: Eagerly adding ${peerId.toBase58()} to mesh for topic $topicId');
    //         currentPeersInMesh.add(peerId);
    //       }
    //     });
    //   } else {
    //     print('[DEBUG] GossipSubRouter.join: No peers found in _pubsub.host.network.peers to eagerly add to mesh for topic $topicId.');
    //   }
    // } else {
    //   print('[DEBUG] GossipSubRouter.join: _pubsub or _pubsub.host is null, cannot perform eager mesh addition for topic $topicId.');
    // }
    // // END DEBUG

    // TODO: Implement actual mesh joining logic (find peers, send GRAFT).
    // Example of tracing a sent GRAFT:
    // for (final peerToGraft in selectedPeers) {
    //   final graftCtrl = pb.ControlGraft()..topicID = topicId;
    //   final controlMsg = pb.ControlMessage()..graft.add(graftCtrl);
    //   final rpc = pb.RPC()..control = controlMsg;
    //   final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
    //     ..sendTo = peerToGraft.toBytes()
    //     ..meta = (trace_pb.TraceEvent_RPCMeta()..control = controlMsg);
    //   _pubsub?.tracer.trace(trace_pb.TraceEvent(
    //     type: trace_pb.TraceEvent_Type.SEND_RPC,
    //     peerID: peerToGraft.toBytes(),
    //     sendRPC: sendRpcTrace
    //   ));
    //   _rpcQueueManager.sendRpc(peerToGraft, rpc, protocolId: gossipSubIDv11);
    // }
  }

  @override
  Future<void> leave(Topic topic) async {
    final topicId = topic.name;
    print('GossipSubRouter: Leaving topic $topicId');
    final leaveTrace = trace_pb.TraceEvent_Leave()..topic = topicId;
    _pubsub?.tracer.trace(trace_pb.TraceEvent()
      ..type = trace_pb.TraceEvent_Type.LEAVE 
      ..peerID = _pubsub?.host.id.toBytes() ?? <int>[] // Local peer ID for JOIN/LEAVE events
      ..leave = leaveTrace
    );

    final meshPeers = mesh[topicId];
    if (meshPeers != null && meshPeers.isNotEmpty) {
      print('GossipSubRouter: TODO - Send PRUNE to ${meshPeers.length} peers for topic $topicId.');
      // Example of tracing a sent PRUNE:
      // for (final peerToPrune in List<PeerId>.from(meshPeers)) {
      //   final pruneCtrl = pb.ControlPrune()..topicID = topicId;
      //   // Add PX peers to pruneCtrl.peers if any
      //   final controlMsg = pb.ControlMessage()..prune.add(pruneCtrl);
      //   final rpc = pb.RPC()..control = controlMsg;
      //   final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
      //     ..sendTo = peerToPrune.toBytes()
      //     ..meta = (trace_pb.TraceEvent_RPCMeta()..control = controlMsg);
      //   _pubsub?.tracer.trace(trace_pb.TraceEvent(
      //     type: trace_pb.TraceEvent_Type.SEND_RPC,
      //     peerID: peerToPrune.toBytes(),
      //     sendRPC: sendRpcTrace
      //   ));
      //   _rpcQueueManager.sendRpc(peerToPrune, rpc, protocolId: gossipSubIDv11);
      // }
    }

    mesh.remove(topicId);
    fanout.remove(topicId);
    fanoutLastPublished.remove(topicId);
  }

  @override
  Future<void> start() async {
    _mcache.start();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(params.fanoutTTL, (_) => _heartbeat());
    print('GossipSubRouter started, mcache and heartbeat timers initiated.');
  }

  @override
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _mcache.dispose();
    print('GossipSubRouter stopped, mcache and heartbeat timers stopped.');
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

  void _heartbeat() {
    print('GossipSubRouter: Heartbeat tick');
    final now = DateTime.now();

    // Refresh scores for all known peers
    _pubsub?.refreshScores();

    // Opportunistic Grafting
    // Iterate over all known topics we are subscribed to
    _pubsub?.getTopics().forEach((topicId) {
      mesh.putIfAbsent(topicId, () => <PeerId>{}); // Ensure mesh entry exists
      final currentMeshPeers = mesh[topicId]!;
      
      if (currentMeshPeers.length >= params.DHigh) {
        return; // Mesh is full or overfull, no room for opportunistic grafts
      }

      final potentialPeers = _pubsub?.host.network.peers.toList() ?? [];
      potentialPeers.shuffle(); // Randomize to give different peers a chance over time

      for (final peerId in potentialPeers) {
        if (peerId == _pubsub?.host.id) continue;
        if (currentMeshPeers.contains(peerId)) continue; // Already in mesh

        final score = _pubsub?.getPeerScore(peerId) ?? -double.infinity;
        if (score >= params.opportunisticGraftScoreThreshold) {
          if (currentMeshPeers.length < params.DHigh) { // Double check before grafting
            print('Heartbeat: Opportunistically GRAFTing ${peerId.toBase58()} to topic $topicId (score: $score)');
            final graftCtrl = pb.ControlGraft()..topicID = topicId;
            final controlMsg = pb.ControlMessage()..graft.add(graftCtrl);
            final rpc = pb.RPC()..control = controlMsg;
            
            final controlMeta = trace_pb.TraceEvent_ControlMeta();
            controlMsg.graft.forEach((graft) { // Assuming controlMsg is pb.ControlMessage
              controlMeta.graft.add(trace_pb.TraceEvent_ControlGraftMeta()..topic = graft.topicID);
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
            _rpcQueueManager.sendRpc(peerId, rpc, protocolId: gossipSubIDv11);
            mesh[topicId]!.add(peerId); // Optimistically add
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

        print('Heartbeat: Topic $topicId mesh too small ($currentMeshSize < ${params.DLow}). Need $needed more peers. Attempting to find and GRAFT.');

        // Get potential peers: all connected peers.
        var potentialPeers = _pubsub?.host.network.peers.toList() ?? [];
        
        // Filter out self, peers already in mesh, using permissive scoring for new peers.
        potentialPeers = potentialPeers.where((peerId) {
          if (peerId == _pubsub?.host.id) return false; // Don't graft self
          if (currentMeshPeers.contains(peerId)) return false; // Already in mesh

          final peerScoreObj = _pubsub?.getPeerScoreObject(peerId);
          if (peerScoreObj == null) {
            // No score object exists - this is a new peer, allow it
            print('Heartbeat: Allowing new peer ${peerId.toBase58()} for topic $topicId (no score history)');
            return true;
          }
          
          final score = peerScoreObj.score;
          
          // Check if this is a "new" peer (recently connected, minimal interaction)
          final isNewPeer = _isNewPeer(peerScoreObj);
          if (isNewPeer) {
            // For new peers, use a more permissive threshold
            final permissiveThreshold = params.DScore - 5.0;
            if (score >= permissiveThreshold) {
              print('Heartbeat: Allowing new peer ${peerId.toBase58()} for topic $topicId (score: $score, permissive threshold: $permissiveThreshold)');
              return true;
            }
          }
          
          // For established peers, use normal threshold
          if (score >= params.DScore) {
            return true;
          }
          
          print('Heartbeat: Excluding peer ${peerId.toBase58()} for topic $topicId (score: $score, threshold: ${params.DScore}, isNew: $isNewPeer)');
          return false;
        }).toList();

        if (potentialPeers.isEmpty) {
          print('Heartbeat: No suitable peers found with normal criteria for topic $topicId.');
          
          // Fallback: Try with even more permissive criteria
          var fallbackPeers = _pubsub?.host.network.peers.toList() ?? [];
          fallbackPeers = fallbackPeers.where((peerId) {
            if (peerId == _pubsub?.host.id) return false;
            if (currentMeshPeers.contains(peerId)) return false;
            
            // Only exclude peers with very bad scores (e.g., < -10.0)
            final score = _pubsub?.getPeerScore(peerId) ?? 0.0; // Default to 0 instead of -infinity
            return score >= -10.0;
          }).toList();
          
          if (fallbackPeers.isNotEmpty) {
            print('Heartbeat: Using fallback criteria, found ${fallbackPeers.length} peers for topic $topicId.');
            potentialPeers = fallbackPeers;
          } else {
            print('Heartbeat: No suitable peers found even with fallback criteria for topic $topicId.');
            return;
          }
        }

        potentialPeers.shuffle(); // Randomize selection

        final peersToGraft = potentialPeers.take(min(needed, potentialPeers.length)).toList();

        for (final peerToGraft in peersToGraft) {
          print('Heartbeat: Sending GRAFT to ${peerToGraft.toBase58()} for topic $topicId.');
          final graftCtrl = pb.ControlGraft()..topicID = topicId;
          final controlMsg = pb.ControlMessage()..graft.add(graftCtrl);
          final rpc = pb.RPC()..control = controlMsg;
          
          final controlMeta = trace_pb.TraceEvent_ControlMeta();
           controlMsg.graft.forEach((graft) { // Assuming controlMsg is pb.ControlMessage
            controlMeta.graft.add(trace_pb.TraceEvent_ControlGraftMeta()..topic = graft.topicID);
          });
          final rpcMeta = trace_pb.TraceEvent_RPCMeta()..control = controlMeta;
          final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
            ..sendTo = peerToGraft.toBytes()
            ..meta = rpcMeta;
          _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.SEND_RPC
            ..peerID = peerToGraft.toBytes()
            ..sendRPC = sendRpcTrace
          );
          _rpcQueueManager.sendRpc(peerToGraft, rpc, protocolId: gossipSubIDv11);
          // Optimistically add to mesh, will be confirmed if peer accepts GRAFT (not handled here)
          // Or, wait for GRAFT ACK if that's part of the protocol (GossipSub v1.1 doesn't have GRAFT ACKs)
          // For now, we assume GRAFT implies an attempt to join, actual mesh state updates on receiving messages or PRUNE.
          // However, the spec implies we add them to our mesh when we send GRAFT.
          mesh[topicId]!.add(peerToGraft); 
        }
      } else if (currentMeshSize > params.DHigh) {
        final excess = currentMeshSize - params.D; // Number of peers to prune to reach D
        print('Heartbeat: Topic $topicId mesh too large ($currentMeshSize > ${params.DHigh}). Need to prune $excess peers.');

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
          print('Heartbeat: Sending PRUNE to ${peerToPrune.toBase58()} for topic $topicId.');
          
          // Construct PRUNE control message
          final pruneCtrl = pb.ControlPrune()..topicID = topicId;
          
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
            pruneCtrl.peers.addAll(pxPeers);
            print('Heartbeat: Adding ${pxPeers.length} PX peers to PRUNE for ${peerToPrune.toBase58()} on topic $topicId.');
          }

          // TODO: Add backoff logic for PRUNE as per spec (ControlPrune.backoff)
          final controlMsg = pb.ControlMessage()..prune.add(pruneCtrl);
          final rpc = pb.RPC()..control = controlMsg;

          final controlMeta = trace_pb.TraceEvent_ControlMeta();
          controlMsg.prune.forEach((prune) { // Assuming controlMsg is pb.ControlMessage
            final pruneMeta = trace_pb.TraceEvent_ControlPruneMeta()..topic = prune.topicID;
            // Assuming prune.peers are List<pb.PeerInfo> and TraceEvent_ControlPruneMeta.peers is List<List<int>>
            prune.peers.forEach((pxPeer) => pruneMeta.peers.add(pxPeer.peerID));
            controlMeta.prune.add(pruneMeta);
          });
          final rpcMeta = trace_pb.TraceEvent_RPCMeta()..control = controlMeta;
          final sendRpcTrace = trace_pb.TraceEvent_SendRPC()
            ..sendTo = peerToPrune.toBytes()
            ..meta = rpcMeta;
           _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.SEND_RPC
            ..peerID = peerToPrune.toBytes()
            ..sendRPC = sendRpcTrace
          );
          _rpcQueueManager.sendRpc(peerToPrune, rpc, protocolId: gossipSubIDv11);
          
          // Remove from local mesh
          mesh[topicId]!.remove(peerToPrune);

          // Also trace the PRUNE event itself
          final pruneTrace = trace_pb.TraceEvent_Prune()
            ..peerID = peerToPrune.toBytes() // The peer we are pruning
            ..topic = topicId;
           _pubsub?.tracer.trace(trace_pb.TraceEvent()
            ..type = trace_pb.TraceEvent_Type.PRUNE
            ..peerID = peerToPrune.toBytes()
            ..prune = pruneTrace
          );
        }
      }
    });

    List<String> topicsToRemoveFromFanout = [];
    fanout.forEach((topicId, fanoutPeers) {
      final lastPub = fanoutLastPublished[topicId];
      if (lastPub == null || now.difference(lastPub) > params.fanoutTTL) {
        print('Heartbeat: Fanout TTL expired for topic $topicId. Removing from fanout.');
        topicsToRemoveFromFanout.add(topicId);
      } else if (fanoutPeers.length < params.D) {
        final needed = params.D - fanoutPeers.length;
        print('Heartbeat: Fanout for topic $topicId too small (${fanoutPeers.length} < ${params.D}). Need $needed more fanout peers.');

        var potentialFanoutPeers = _pubsub?.host.network.peers.toList() ?? [];
        potentialFanoutPeers = potentialFanoutPeers.where((peerId) {
          if (peerId == _pubsub?.host.id) return false;
          if (fanoutPeers.contains(peerId)) return false; // Already in fanout
          if (mesh[topicId]?.contains(peerId) ?? false) return false; // Already in mesh for this topic

          final score = _pubsub?.getPeerScore(peerId) ?? -double.infinity;
          return score >= params.DScore; // Ensure good score
        }).toList();

        if (potentialFanoutPeers.isEmpty) {
          print('Heartbeat: No suitable peers found to add to fanout for topic $topicId.');
        } else {
          potentialFanoutPeers.shuffle();
          final peersToAdd = potentialFanoutPeers.take(min(needed, potentialFanoutPeers.length)).toList();
          for (final peerToAdd in peersToAdd) {
            print('Heartbeat: Adding ${peerToAdd.toBase58()} to fanout for topic $topicId.');
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

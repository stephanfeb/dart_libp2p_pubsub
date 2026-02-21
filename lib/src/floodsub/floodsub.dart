import 'dart:async';
import 'dart:collection'; // For HashSet

import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../core/pubsub.dart';
import '../core/message.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/topic.dart';
import '../core/router.dart';
import '../core/comm.dart' show floodSubID; // Assuming floodSubID is defined for FloodSub protocol

/// Implementation of the FloodSub routing protocol.
///
/// FloodSub is a simple router that floods messages to all connected peers
/// that are subscribed to the relevant topics.
class FloodSubRouter implements Router {
  PubSub? _pubsub;
  
  /// Set of all known peers that support FloodSub.
  final Set<PeerId> _peers = HashSet<PeerId>();
  
  /// Topics this node is subscribed to.
  final Set<String> _subscribedTopics = HashSet<String>();

  // FloodSub doesn't have complex parameters like GossipSub.

  FloodSubRouter();

  @override
  Future<void> attach(PubSub pubsub) async {
    _pubsub = pubsub;
    // TODO: Register FloodSub protocol ID with PubSub's comms layer.
    // This would involve calling something like:
    // _pubsub!.comms.setProtocolHandler(floodSubID, _handleIncomingRpcWrapper);
    // where _handleIncomingRpcWrapper adapts to call this.handleRpc.
    print('FloodSubRouter attached to PubSub.');
  }

  @override
  Future<void> detach() async {
    // TODO: Unregister protocol handler.
    _pubsub = null;
    _peers.clear();
    _subscribedTopics.clear();
    print('FloodSubRouter detached.');
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    if (protocolId == floodSubID) {
      print('FloodSubRouter: Peer added - ${peerId.toBase58()} supporting $protocolId');
      _peers.add(peerId);
      // TODO: FloodSub might involve sending current subscriptions to new peers,
      // or peers announce their subscriptions upon connection.
      // For now, we just track the peer.
    } else {
      print('FloodSubRouter: Peer ${peerId.toBase58()} added with non-FloodSub protocol $protocolId. Ignoring for FloodSub.');
    }
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    if (_peers.remove(peerId)) {
      print('FloodSubRouter: Peer removed - ${peerId.toBase58()}');
    }
  }

  @override
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc) async {
    print('FloodSubRouter: Handling RPC from ${peerId.toBase58()}');
    
    // FloodSub primarily processes published messages.
    // It doesn't have complex control messages like GossipSub's GRAFT/PRUNE.
    // It might observe SUBSCRIBE/UNSUBSCRIBE messages if they are part of the RPC.
    if (rpc.subscriptions.isNotEmpty) {
      for (final subOpt in rpc.subscriptions) {
        // In a simple FloodSub, other peers' subscriptions might not be explicitly tracked
        // for routing decisions beyond knowing they are part of the topic.
        // We typically flood to all peers in the topic.
        print('FloodSubRouter: Peer $peerId sent subscription for ${subOpt.topicid} (subscribe: ${subOpt.subscribe}) - noted.');
      }
    }

    if (rpc.publish.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        // TODO: Validate the message (size, origin, etc.) - this should use PubSub's validation.
        // For now, assume valid.
        
        // Check if we are subscribed to this message's topic.
        // Floodsub typically delivers if subscribed.
        if (_subscribedTopics.contains(msgProto.topic)) {
          print('FloodSubRouter: Received message on subscribed topic ${msgProto.topic} from $peerId. Delivering locally.');
          final pubSubMsg = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
          _pubsub?.deliverReceivedMessage(pubSubMsg); // Corrected method name
        } else {
          print('FloodSubRouter: Received message on unsubscribed topic ${msgProto.topic} from $peerId. Ignoring for local delivery.');
        }
        
        // Forward (flood) the message to other peers, excluding the sender.
        // This is a naive flood; a real implementation might have seen-message tracking (like mcache).
        print('FloodSubRouter: Flooding message on topic ${msgProto.topic} from $peerId to other peers.');
        final rpcToSend = pb.RPC()..publish.add(msgProto);
        for (final otherPeerId in _peers) {
          if (otherPeerId == peerId) continue; // Don't send back to sender

          // TODO: Check if otherPeerId is interested in the topic (if FloodSub variant supports it).
          // For basic flood, send to all.
          try {
            _pubsub?.comms.sendRpc(otherPeerId, rpcToSend, floodSubID);
          } catch (e) {
            print('FloodSubRouter: Failed to flood message to peer ${otherPeerId.toBase58()}: $e');
          }
        }
      }
    }
    // FloodSub delivers messages directly above, so return empty set
    // to prevent PubSub from double-delivering.
    return {};
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final topicId = message.topic;
    print('FloodSubRouter: Publishing message for topic $topicId');

    if (_pubsub == null) {
      print('FloodSubRouter: PubSub not attached. Cannot publish.');
      return;
    }

    // TODO: Add to a "seen" cache for this router to prevent re-flooding if received back.
    // For now, this simple version doesn't have its own mcache.

    final rpcToSend = pb.RPC()..publish.add(message.rpcMessage);

    int floodCount = 0;
    for (final peerId in _peers) {
      // Don't send to self if message originated locally (receivedFrom is null)
      // or if the peer is the original sender of a relayed message.
      if (message.receivedFrom == peerId) continue; 
      
      // In basic FloodSub, we flood to all connected peers.
      // More advanced versions might check if peer is subscribed to the topic.
      print('FloodSubRouter: Flooding message on topic $topicId to peer ${peerId.toBase58()}');
      try {
        _pubsub!.comms.sendRpc(peerId, rpcToSend, floodSubID);
        floodCount++;
      } catch (e) {
        print('FloodSubRouter: Failed to flood message to peer ${peerId.toBase58()}: $e');
      }
    }
    print('FloodSubRouter: Message for topic $topicId flooded to $floodCount peers.');
  }

  @override
  Future<void> join(Topic topic) async {
    print('FloodSubRouter: Joining topic ${topic.name}');
    _subscribedTopics.add(topic.name);
    // FloodSub doesn't typically send control messages like GRAFT.
    // It might announce its new subscriptions to peers if the protocol variant includes that.
  }

  @override
  Future<void> leave(Topic topic) async {
    print('FloodSubRouter: Leaving topic ${topic.name}');
    _subscribedTopics.remove(topic.name);
    // FloodSub doesn't typically send control messages like PRUNE.
  }

  @override
  Future<void> start() async {
    // FloodSub is mostly stateless and event-driven, may not need a start action
    // beyond what attach() does (like registering protocol handler).
    print('FloodSubRouter started.');
  }

  @override
  Future<void> stop() async {
    // Similar to start(), may not need specific stop actions beyond detach().
    print('FloodSubRouter stopped.');
  }
}

import 'dart:async';
import 'dart:collection'; // For HashSet
import 'dart:math'; // For Random

import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../core/pubsub.dart';
import '../core/message.dart';
import '../pb/rpc.pb.dart' as pb;
import '../core/topic.dart';
import '../core/router.dart';
import '../core/comm.dart'; // For a potential RandomSub protocol ID

// TODO: Define a specific protocol ID for RandomSub if it's different from FloodSub/GossipSub.
// For now, let's assume it might reuse floodSubID or have its own.
// const String randomSubID = '/randomsub/1.0.0'; // Example

/// Implementation of the RandomSub routing protocol.
///
/// RandomSub is a simple router that forwards messages to a random subset of
/// connected peers that are subscribed to the relevant topics.
class RandomSubRouter implements Router {
  PubSub? _pubsub;
  
  final Set<PeerId> _peers = HashSet<PeerId>();
  final Set<String> _subscribedTopics = HashSet<String>();
  final Random _random = Random();

  /// The number of peers to forward a message to.
  /// TODO: Make this configurable.
  final int _randomSubDegree;

  RandomSubRouter({int randomSubDegree = 3}) : _randomSubDegree = randomSubDegree;

  @override
  Future<void> attach(PubSub pubsub) async {
    _pubsub = pubsub;
    // TODO: Register RandomSub protocol ID (if specific) with PubSub's comms layer.
    // e.g., _pubsub!.comms.setProtocolHandler(randomSubID, _handleIncomingRpcWrapper);
    print('RandomSubRouter attached to PubSub.');
  }

  @override
  Future<void> detach() async {
    _pubsub = null;
    _peers.clear();
    _subscribedTopics.clear();
    print('RandomSubRouter detached.');
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    // TODO: Check if protocolId matches a specific RandomSub ID.
    // For now, assume any peer added might be a candidate.
    print('RandomSubRouter: Peer added - ${peerId.toBase58()} (protocol: $protocolId)');
    _peers.add(peerId);
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    if (_peers.remove(peerId)) {
      print('RandomSubRouter: Peer removed - ${peerId.toBase58()}');
    }
  }

  @override
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc) async {
    print('RandomSubRouter: Handling RPC from ${peerId.toBase58()}');
    // RandomSub, like FloodSub, primarily processes published messages.
    // It doesn't have complex control messages.
    if (rpc.publish.isNotEmpty) {
      for (final msgProto in rpc.publish) {
        // TODO: Validate message.
        if (_subscribedTopics.contains(msgProto.topic)) {
          print('RandomSubRouter: Received message on subscribed topic ${msgProto.topic} from $peerId. Delivering locally.');
          final pubSubMsg = PubSubMessage(rpcMessage: msgProto, receivedFrom: peerId);
          _pubsub?.deliverReceivedMessage(pubSubMsg);
        }
        
        // Forward to a random subset of other peers.
        // TODO: Implement seen-message tracking to avoid re-broadcasting.
        _forwardMessage(msgProto, peerId);
      }
    }
    // RandomSub delivers messages directly above, so return empty set
    // to prevent PubSub from double-delivering.
    return {};
  }

  void _forwardMessage(pb.Message msgProto, PeerId originalSender) {
    if (_peers.isEmpty) return;

    final List<PeerId> candidates = List.from(_peers.where((p) => p != originalSender));
    if (candidates.isEmpty) return;

    candidates.shuffle(_random);
    
    final int count = min(candidates.length, _randomSubDegree);
    final rpcToSend = pb.RPC()..publish.add(msgProto);

    print('RandomSubRouter: Forwarding message on topic ${msgProto.topic} to $count random peers.');
    for (int i = 0; i < count; i++) {
      final peerToSendTo = candidates[i];
      try {
        // TODO: Use the correct protocol ID for RandomSub. Using floodSubID as placeholder.
        _pubsub?.comms.sendRpc(peerToSendTo, rpcToSend, floodSubID); 
      } catch (e) {
        print('RandomSubRouter: Failed to forward message to peer ${peerToSendTo.toBase58()}: $e');
      }
    }
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final topicId = message.topic;
    print('RandomSubRouter: Publishing message for topic $topicId');

    if (_pubsub == null) {
      print('RandomSubRouter: PubSub not attached. Cannot publish.');
      return;
    }
    // TODO: Add to a "seen" cache.
    _forwardMessage(message.rpcMessage, _pubsub!.host.id); // originalSender is self
  }

  @override
  Future<void> join(Topic topic) async {
    print('RandomSubRouter: Joining topic ${topic.name}');
    _subscribedTopics.add(topic.name);
  }

  @override
  Future<void> leave(Topic topic) async {
    print('RandomSubRouter: Leaving topic ${topic.name}');
    _subscribedTopics.remove(topic.name);
  }

  @override
  Future<void> start() async {
    print('RandomSubRouter started.');
  }

  @override
  Future<void> stop() async {
    print('RandomSubRouter stopped.');
  }
}

import 'dart:async';
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/rcmgr.dart'; // For NullResourceManager
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/peerstore.dart'; // For AddressTTL
import 'package:dart_libp2p/p2p/host/eventbus/basic.dart' as p2p_event_bus;
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_mgr;
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart'; // For GossipSub, Message
import 'package:dart_udx/dart_udx.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../real_net_stack.dart'; // For Libp2pNode and createLibp2pNode

final Logger _logger = Logger("GossipSubIntegrationTest");

// Helper class to encapsulate node and PubSub (with GossipSubRouter) creation
class _NodeWithGossipSub {
  late Libp2pNode nodeDetails;
  late PubSub pubsub; // Changed to PubSub
  late Host host;
  late PeerId peerId;
  late UDX _udxInstance; // Keep instance to close if necessary

  static Future<_NodeWithGossipSub> create({String? userAgentPrefix}) async {
    final helper = _NodeWithGossipSub();

    helper._udxInstance = UDX();
    // Using NullResourceManager as it's often suitable for tests not focusing on resource limits
    final resourceManager = NullResourceManager(); 
    final connManager = p2p_conn_mgr.ConnectionManager();
    final eventBus = p2p_event_bus.BasicBus();

    helper.nodeDetails = await createLibp2pNode(
      udxInstance: helper._udxInstance,
      resourceManager: resourceManager,
      connManager: connManager,
      hostEventBus: eventBus,
      userAgentPrefix: userAgentPrefix ?? 'gossipsub-test-node',
    );
    helper.host = helper.nodeDetails.host;
    helper.peerId = helper.nodeDetails.peerId;

    final router = GossipSubRouter();
    // The PubSub constructor takes host and router.
    // It internally calls router.attach(this).
    helper.pubsub = PubSub(helper.host, router);

    // pubsub.start() will be called separately in test's setUp.
    // This will start both the PubSub service and its attached router.
    return helper;
  }

  Future<void> startPubSub() async {
    // PubSub.start() will also start its router.
    await pubsub.start();
    _logger.info('Peer ${peerId.toBase58().substring(0,10)} PubSub (with GossipSubRouter) started.');
  }

  Future<void> stop() async {
    _logger.info('Stopping Peer ${peerId.toBase58().substring(0,10)}...');
    // PubSub.stop() will also stop its router.
    await pubsub.stop();
    await host.close();
    // If UDX instances need explicit disposal and it's safe to do so, add:
    // await _udxInstance.dispose();
    _logger.info('Peer ${peerId.toBase58().substring(0,10)} stopped.');
  }
}

void main() {
  // Configure logging
  Logger.root.level = Level.INFO; // Use Level.ALL for very detailed logs
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      print('ERROR: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('STACKTRACE: ${record.stackTrace}');
    }
  });

  group('GossipSub Integration Tests with Real Network Stack', () {
    late _NodeWithGossipSub nodeA;
    late _NodeWithGossipSub nodeB;

    setUp(() async {
      _logger.info('Setting up test nodes...');
      nodeA = await _NodeWithGossipSub.create(userAgentPrefix: 'NodeA');
      nodeB = await _NodeWithGossipSub.create(userAgentPrefix: 'NodeB');

      await nodeA.startPubSub();
      await nodeB.startPubSub();

      _logger.info('Node A: ${nodeA.peerId.toBase58()} @ ${nodeA.host.addrs}');
      _logger.info('Node B: ${nodeB.peerId.toBase58()} @ ${nodeB.host.addrs}');

      // Add peer info to peerstore for successful connection
      if (nodeB.host.addrs.isNotEmpty) {
        nodeA.host.peerStore.addrBook.addAddrs(nodeB.peerId, nodeB.host.addrs, AddressTTL.permanentAddrTTL);
      } else {
        _logger.warning('Node B has no listen addresses. Node A cannot add it to peerstore effectively.');
      }
      if (nodeA.host.addrs.isNotEmpty) {
        nodeB.host.peerStore.addrBook.addAddrs(nodeA.peerId, nodeA.host.addrs, AddressTTL.permanentAddrTTL);
      } else {
        _logger.warning('Node A has no listen addresses. Node B cannot add it to peerstore effectively.');
      }

      // Connect nodes
      var connectedAtoB = false;
      if (nodeA.host.addrs.isNotEmpty && nodeB.host.addrs.isNotEmpty) {
        _logger.info('Attempting to connect Node A to Node B...');
        try {
          await nodeA.host.connect(AddrInfo(nodeB.peerId, nodeB.host.addrs));
          _logger.info('Node A connection attempt to Node B successful.');
          connectedAtoB = true;
        } catch (e, s) {
          _logger.warning('Node A failed to connect to Node B: $e', e, s);
        }
      } else {
         _logger.warning('Skipping connect A to B due to one or both nodes having no listen addresses.');
      }
      
      // Optionally, connect B to A if the transport might be unidirectional or for robustness
      var connectedBtoA = false;
      if (nodeA.host.addrs.isNotEmpty && nodeB.host.addrs.isNotEmpty) {
        _logger.info('Attempting to connect Node B to Node A...');
        try {
          await nodeB.host.connect(AddrInfo(nodeA.peerId, nodeA.host.addrs));
          _logger.info('Node B connection attempt to Node A successful.');
          connectedBtoA = true;
        } catch (e, s) {
          _logger.warning('Node B failed to connect to Node A: $e', e, s);
        }
      } else {
        _logger.warning('Skipping connect B to A due to one or both nodes having no listen addresses.');
      }

      if (!connectedAtoB && !connectedBtoA) {
        _logger.severe('CRITICAL: Nodes A and B could not establish any connection. Test will likely fail.');
      }

      // Allow time for GossipSub peers to connect and exchange control messages (heartbeats, etc.)
      // This is crucial for the mesh to form.
      _logger.info('Waiting for GossipSub overlay to form (e.g., heartbeats, peer exchange)...');
      await Future.delayed(Duration(seconds: 8)); // Increased delay
      _logger.info('Finished waiting for overlay formation.');
    });

    tearDown(() async {
      _logger.info('Tearing down test nodes...');
      await nodeA.stop();
      await nodeB.stop();
      _logger.info('Test nodes stopped.');
    });

    test('Node A subscribes, Node B publishes, Node A receives the message', () async {
      const topicId = 'test-topic-dogs-and-cats';
      final messagePayload = 'GossipSub rocks on real UDX!';
      final messageData = Uint8List.fromList(utf8.encode(messagePayload));
      final messageReceivedCompleter = Completer<PubSubMessage>(); // Changed Message to PubSubMessage

      // The following lines will likely fail because `GossipSubRouter` does not have `getPeers`.
      // This method belongs to the main `PubSub` class.
      // _logger.info('Node A PubSub Peers for topic $topicId (before subscribe): ${nodeA.pubsub.getPeers(topicId).map((p) => p.toBase58().substring(0,6))}');
      // _logger.info('Node B PubSub Peers for topic $topicId (before subscribe): ${nodeB.pubsub.getPeers(topicId).map((p) => p.toBase58().substring(0,6))}');
      // Commenting them out for now as they are not the primary errors being addressed.
      // These will need to be fixed by correctly using the PubSub API.

      // Node A subscribes to the topic
      final subscriptionA = nodeA.pubsub.subscribe(topicId); // This should now work as pubsub is PubSub
      _logger.info('Node A (${nodeA.peerId.toBase58().substring(0,6)}) subscribed to topic: $topicId');

      final streamSubscription = subscriptionA.stream.listen( // Called listen on subscriptionA.stream
        (message) { // message here is PubSubMessage (actually dynamic from stream, but we expect PubSubMessage)
          if (message is! PubSubMessage) {
            _logger.warning('Received message of unexpected type: ${message.runtimeType}');
            return;
          }
          _logger.info('Node A (${nodeA.peerId.toBase58().substring(0,6)}) received message on topic ${message.topic} from ${message.from.toBase58().substring(0,10)}: "${utf8.decode(message.data)}"');
          // PubSubMessage has 'topic' (String) not 'topicIDs' (List<String>)
          if (message.from == nodeB.peerId && message.topic == topicId && utf8.decode(message.data) == messagePayload) {
            if (!messageReceivedCompleter.isCompleted) {
              messageReceivedCompleter.complete(message);
            }
          }
        },
        onError: (e, s) {
          _logger.severe('Error in Node A subscription stream for topic $topicId: $e', e, s);
          if (!messageReceivedCompleter.isCompleted) {
            messageReceivedCompleter.completeError(e, s);
          }
        },
        onDone: () {
           _logger.info('Node A subscription stream for topic $topicId was closed.');
           if (!messageReceivedCompleter.isCompleted) {
             messageReceivedCompleter.completeError(StateError('Subscription stream closed before message received.'));
           }
        }
      );

      // Allow time for subscription to propagate and mesh to adjust
      _logger.info('Waiting for subscription to propagate and mesh to adjust...');
      await Future.delayed(Duration(seconds: 5)); // This delay is important for GossipSub

      // Accessing mesh peers: pubsub.router is the Router, cast to GossipSubRouter to access 'mesh'
      final nodeAMesh = (nodeA.pubsub.router as GossipSubRouter).mesh[topicId]?.map((p) => p.toBase58().substring(0,6)).toList() ?? [];
      final nodeBMesh = (nodeB.pubsub.router as GossipSubRouter).mesh[topicId]?.map((p) => p.toBase58().substring(0,6)).toList() ?? [];
      _logger.info('Node A Mesh for topic $topicId: $nodeAMesh');
      _logger.info('Node B Mesh for topic $topicId: $nodeBMesh');

      // Node B publishes a message
      _logger.info('Node B (${nodeB.peerId.toBase58().substring(0,6)}) publishing message to topic: $topicId');
      await nodeB.pubsub.publish(topicId, messageData); // This should now work
      _logger.info('Node B (${nodeB.peerId.toBase58().substring(0,6)}) published message: "$messagePayload"');

      try {
        final receivedMessage = await messageReceivedCompleter.future.timeout(Duration(seconds: 20)); // Timeout for receiving the message
        
        expect(receivedMessage.from, equals(nodeB.peerId), reason: "Message 'from' field should match Node B's PeerId.");
        expect(receivedMessage.data, equals(messageData), reason: "Message data should match what Node B sent.");
        expect(receivedMessage.topic, equals(topicId), reason: "Message topic should match the subscribed topic."); // Changed topicIDs to topic
        _logger.info('Test PASSED: Node A correctly received the message from Node B.');

      } catch (e,s) {
        _logger.severe('Test FAILED: Node A did not receive the message from Node B as expected, or an error occurred.', e, s);
        _logger.info('Diagnostic Info:');
        _logger.info('Node A (${nodeA.peerId.toBase58().substring(0,6)}) connected peers: ${nodeA.host.network.peers.map((p) => p.toBase58().substring(0,6))}');
        _logger.info('Node B (${nodeB.peerId.toBase58().substring(0,6)}) connected peers: ${nodeB.host.network.peers.map((p) => p.toBase58().substring(0,6))}');
        
        // PubSub class does not have a direct getPeers(topicId) method.
        // We can log mesh peers from the router.
        final currentAMesh = (nodeA.pubsub.router as GossipSubRouter).mesh[topicId]?.map((p) => p.toBase58().substring(0,6)).toList() ?? [];
        final currentBMesh = (nodeB.pubsub.router as GossipSubRouter).mesh[topicId]?.map((p) => p.toBase58().substring(0,6)).toList() ?? [];
        _logger.info('Node A Mesh for topic $topicId (at failure): $currentAMesh');
        _logger.info('Node B Mesh for topic $topicId (at failure): $currentBMesh');
        
        fail('Node A did not receive the message from Node B. Error: $e');
      } finally {
        await streamSubscription.cancel();
        await nodeA.pubsub.unsubscribe(topicId); // This should now work
        _logger.info('Node A (${nodeA.peerId.toBase58().substring(0,6)}) unsubscribed from topic: $topicId');
      }
    }, timeout: Timeout(Duration(seconds: 45))); // Overall test case timeout
  });
}

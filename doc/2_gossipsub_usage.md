# 2. Basic Pub/Sub Operations

Once you have a running libp2p `Host`, you can add publish-subscribe capabilities using the `PubSub` service. This guide covers the essential workflow for sending and receiving messages using GossipSub.

The examples here are based on `test/integration/gossipsub_integration_test.dart`.

## 1. Creating a PubSub Instance

The main entry point to the pubsub system is the `PubSub` class. It requires a `Host` and a `Router`. For GossipSub, you'll use the `GossipSubRouter`.

```dart
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p/core/host/host.dart';

// Assume 'host' is a fully configured and running Libp2p Host from the previous guide.
Host host = ...;

// 1. Create a GossipSubRouter instance.
final router = GossipSubRouter();

// 2. Create a PubSub instance, passing the host and the router.
final pubsub = PubSub(host, router);
```

The `PubSub` constructor automatically attaches the router, so they are linked.

## 2. Starting the PubSub Service

Before you can publish or subscribe, you must start the `PubSub` service. This will also start the underlying router (e.g., `GossipSubRouter`), which begins its own processes like heartbeating.

```dart
// Start the PubSub service and the attached router.
await pubsub.start();
```

## 3. Connecting Nodes

For messages to flow between peers, they must first be connected at the network level. You can use the standard `host.connect()` method. After a connection is established, GossipSub peers will discover each other and may form a mesh.

```dart
// Assume we have two nodes, nodeA and nodeB.
// Add nodeB's address info to nodeA's peerstore.
nodeA.host.peerStore.addrBook.addAddrs(nodeB.peerId, nodeB.host.addrs, AddressTTL.permanentAddrTTL);

// Connect nodeA to nodeB.
await nodeA.host.connect(AddrInfo(nodeB.peerId, nodeB.host.addrs));

// It's crucial to allow some time for the GossipSub overlay to form.
// Peers exchange control messages (like heartbeats) to build the mesh.
await Future.delayed(Duration(seconds: 8));
```

## 4. Subscribing to a Topic

To receive messages, a node must subscribe to one or more topics. The `pubsub.subscribe()` method returns a `Subscription` object, which contains a `Stream` of incoming messages for that topic.

```dart
const topicId = 'news-alerts';

// Node A subscribes to the topic.
final subscription = nodeA.pubsub.subscribe(topicId);

// Listen for incoming messages on the subscription's stream.
subscription.stream.listen((message) {
  // The 'message' object is a PubSubMessage.
  print('Received message:');
  print('  Topic: ${message.topic}');
  print('  From: ${message.from.toBase58()}');
  print('  Data: "${utf8.decode(message.data)}"');
});
```

### The `PubSubMessage` Object

The `PubSubMessage` class encapsulates a received message and contains the following important fields:
-   `from`: The `PeerId` of the original publisher.
-   `data`: The raw message payload as a `Uint8List`.
-   `topic`: The topic this message was published to.
-   `seqno`: A sequence number from the publisher.
-   `receivedFrom`: The `PeerId` of the peer that sent us this message.

## 5. Publishing a Message

Any peer can publish a message to a topic. The message will be propagated through the GossipSub mesh to all subscribed peers.

```dart
const topicId = 'news-alerts';
final messagePayload = 'Big news: Libp2p is awesome!';
final messageData = Uint8List.fromList(utf8.encode(messagePayload));

// Node B publishes a message to the topic.
await nodeB.pubsub.publish(topicId, messageData);
```

If Node A is subscribed to `news-alerts` and is part of the same GossipSub mesh as Node B, it will receive this message in its subscription stream.

## 6. Unsubscribing and Stopping

When you no longer need to receive messages on a topic, you can unsubscribe.

```dart
// Unsubscribe from the topic.
// This will also cause the router to send PRUNE messages to its mesh peers.
await nodeA.pubsub.unsubscribe(topicId);
```

To shut down the entire pubsub service, call `stop()`. This will stop the router and all associated background tasks.

```dart
await pubsub.stop();
```

---

**Next**: [3. GossipSub Deep Dive](./3_gossipsub_deep_dive.md)

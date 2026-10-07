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

## 6. Validating Messages

A node forwards a message to its mesh peers and delivers it to its subscribers only after the message passes validation. Register a validator for each topic to control what your node relays. The model is the same as `RegisterTopicValidator` in go-libp2p-pubsub.

```dart
pubsub.registerTopicValidator('news-alerts', (PeerId receivedFrom, PubSubMessage msg) async {
  final text = utf8.decode(msg.data, allowMalformed: true);
  if (text.length > 1000) return ValidationResult.reject; // invalid: penalise the sender
  if (await isStale(text)) return ValidationResult.ignore; // valid, but not wanted: no penalty
  return ValidationResult.accept;
}, timeout: Duration(seconds: 2), concurrency: 64);

// Later:
pubsub.unregisterTopicValidator('news-alerts');
```

-   **accept**: the message is forwarded to the mesh and delivered to subscribers.
-   **reject**: the message is dropped, and the peer that delivered it (`receivedFrom`, not the author `msg.from`) gets an invalid-message penalty on the topic. Return `reject` only for messages that are really invalid; honest peers forward any message that their own validator accepts.
-   **ignore**: the message is dropped without a penalty.

The checks run in this order:
1.  **Duplicates.** A message whose ID was seen in the last `GossipSubParams.seenMessagesTTL` (default 2 minutes) is dropped before validation. A message is marked seen before it is validated, whatever the result, so a validator runs once per message. A peer that sends a copy of a message that was rejected is penalised too.
2.  **Throttle.** At most `validateThrottle` messages (default 8192, a `PubSub` constructor argument) are in validation at the same time. More messages are dropped as `ignore`.
3.  **Structure and signature.** A malformed or badly signed message is rejected.
4.  **Validators of `registerMessageValidator`** (legacy, synchronous, all topics): `true` accepts and `false` rejects.
5.  **The topic validator.** It can be async. A run that takes longer than its `timeout` (default: the `PubSub` `validatorTimeout`, 5 seconds; `Duration.zero` means no limit) gives `ignore`. If more than `concurrency` runs (default 1024) are active for the topic, the message is dropped as `ignore`. A validator that throws gives `ignore`.

Validators also run on the messages that your node publishes; `receivedFrom` is then the local peer ID. Dropped messages are traced as `REJECT_MESSAGE` with a reason (`validation failed`, `validation ignored`, `validation throttled`, `validation timeout`, `invalid signature`, `invalid message`).

## 7. Unsubscribing and Stopping

When you no longer need to receive messages on a topic, you can unsubscribe.

```dart
// Unsubscribe from the topic.
// This will also cause the router to send PRUNE messages to its mesh peers.
await nodeA.pubsub.unsubscribe(topicId);
```

To shut down the entire pubsub service, call `stop()`. This stops the router, removes all peers from it and closes all pubsub streams, waiting at most 2 seconds for each.

```dart
await pubsub.stop();
```

`stop()` keeps your subscriptions and validators. Calling `start()` again rejoins the subscribed topics, greets the connected peers again, and the existing subscriptions receive messages again. To end a subscription's stream, cancel the subscription. `stop()` flushes the tracer but does not dispose it: dispose it yourself after the last `stop()`.

---

**Next**: [3. GossipSub Deep Dive](./3_gossipsub_deep_dive.md)

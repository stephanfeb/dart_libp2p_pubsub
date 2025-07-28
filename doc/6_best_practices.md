# 6. Best Practices and Common Pitfalls

Building applications on a distributed system like libp2p requires attention to details that might not be present in centralized systems. This guide covers some best practices and common pitfalls to help you build robust and maintainable applications with `dart-libp2p-pubsub`.

## 1. Message Serialization

The `data` field of a `PubSubMessage` is a raw `Uint8List`. It's up to your application to define a serialization format.

**Best Practice**:
*   **Choose a Standard Format**: Use a well-defined serialization format like Protocol Buffers (Protobuf), JSON, or MessagePack. This avoids ambiguity and makes your protocol easier to debug and extend.
*   **Version Your Messages**: Include a version number in your message structure. This allows you to evolve your message format over time without breaking older clients.

**Pitfall**:
*   Avoid sending raw, unstructured binary data. This makes it very difficult for other developers (or even yourself in the future) to understand and parse the messages.

```dart
// Good: Using JSON with a version field
// { "version": 1, "payload": "your data here" }
final messageMap = {'version': 1, 'payload': 'hello world'};
final messageData = utf8.encode(json.encode(messageMap));
await pubsub.publish(topic, messageData);

// On the receiving end
final receivedMap = json.decode(utf8.decode(message.data));
if (receivedMap['version'] == 1) {
  // process payload
}
```

## 2. Error Handling

The `Subscription.stream` is a standard Dart `Stream`, and it can emit errors.

**Best Practice**:
*   **Always Provide an `onError` Handler**: When you `listen` to a subscription stream, always provide an `onError` callback to handle potential issues, such as problems with the underlying network connection or stream processing.

**Pitfall**:
*   Forgetting the `onError` handler can lead to unhandled exceptions that crash your application.

```dart
subscription.stream.listen(
  (message) { /* process message */ },
  onError: (e, s) {
    print('An error occurred on the subscription stream: $e');
    // Decide whether to cancel the subscription or attempt to recover.
  },
  onDone: () {
    print('Subscription stream was closed.');
  }
);
```

## 3. Connection Management

GossipSub operates on top of the libp2p Host's network connections. It does not establish connections itself.

**Best Practice**:
*   **Manage Connections Separately**: Your application is responsible for finding and connecting to other peers. Use a discovery mechanism (like Kademlia DHT, not included in this library) or a bootstrap list to find peers, and then use `host.connect()` to establish a connection.
*   **Monitor Connection Status**: Be aware of peer connection and disconnection events to understand the state of your network.

**Pitfall**:
*   Assuming that joining a topic will automatically connect you to peers. You must be connected at the network layer first before GossipSub can build its mesh.

## 4. Topic Naming Conventions

Topics are simple strings, which offers flexibility but can also lead to issues.

**Best Practice**:
*   **Use a Structured Naming Scheme**: Adopt a clear and consistent naming scheme for your topics. A good practice is to use a hierarchical, path-like structure.
    *   Example: `/myapp/v1/documents/updates`
*   This helps prevent topic collisions with other applications on the same libp2p network and makes your application's purpose clear.

**Pitfall**:
*   Using overly simple topic names like `"test"` or `"chat"`, which could easily collide with other services.

## 5. Graceful Shutdown

The `GossipSubRouter` has background processes like the heartbeat timer.

**Best Practice**:
*   **Always Call `stop()`**: When your application is shutting down, make sure to call `await pubsub.stop()`. This will gracefully stop the router, cancel timers, and clean up resources.

**Pitfall**:
*   Forgetting to call `stop()` can leave dangling processes or timers, which can cause issues or prevent your application from exiting cleanly.

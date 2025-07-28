# 4. Testing Your Application

Testing distributed systems can be complex, but `dart-libp2p-pubsub` is designed to be testable at different levels. The project's own test suite provides excellent examples of how to approach this.

This guide covers two primary strategies for testing your PubSub-enabled application: full integration testing and isolated testing with mocks.

## 1. Full Integration Testing with a Real Network Stack

This is the most comprehensive form of testing, as it verifies that all components of the libp2p stack are working together correctly. It involves spinning up two or more complete libp2p nodes and having them communicate over a real (local) network connection.

The test `test/integration/gossipsub_integration_test.dart` is a perfect example of this approach.

### Key Steps:

1.  **Use a Helper to Create Nodes**: Create a helper function (like `createLibp2pNode` in `test/real_net_stack.dart`) to encapsulate the creation of a full network stack (Host, Swarm, Transport, etc.). This keeps your test code clean.

2.  **Instantiate Multiple Nodes**: In your test's `setUp`, create at least two nodes.

    ```dart
    // From gossipsub_integration_test.dart
    late _NodeWithGossipSub nodeA;
    late _NodeWithGossipSub nodeB;

    setUp(() async {
      nodeA = await _NodeWithGossipSub.create();
      nodeB = await _NodeWithGossipSub.create();
      // ... start pubsub, etc.
    });
    ```

3.  **Connect the Nodes**: Explicitly connect the nodes using their listen addresses.

    ```dart
    // Add peer info to peerstore
    nodeA.host.peerStore.addrBook.addAddrs(nodeB.peerId, nodeB.host.addrs, ...);
    
    // Connect
    await nodeA.host.connect(AddrInfo(nodeB.peerId, nodeB.host.addrs));
    ```

4.  **Allow Time for Overlay Formation**: GossipSub needs time to form its mesh. A short delay after connecting is crucial for tests to be reliable.

    ```dart
    // Allow time for heartbeats and GRAFT messages
    await Future.delayed(Duration(seconds: 8));
    ```

5.  **Perform Actions and Assert**: Subscribe on one node, publish on another, and use a `Completer` to wait for the message to be received.

    ```dart
    final messageReceivedCompleter = Completer<PubSubMessage>();
    subscriptionA.stream.listen((message) {
      messageReceivedCompleter.complete(message);
    });

    await nodeB.pubsub.publish(topicId, messageData);

    final receivedMessage = await messageReceivedCompleter.future.timeout(...);
    expect(receivedMessage.from, equals(nodeB.peerId));
    ```

**When to use this approach**: For end-to-end tests that validate the entire system, from the transport layer up to your application logic.

## 2. Isolated Testing with Mocks

Integration tests can be slow and resource-intensive. For testing specific logic within the PubSub system or your application, you can mock the `Host` and `Network` layers.

The test `test/integration/message_propagation_test.dart` demonstrates this pattern.

### Key Steps:

1.  **Create Mock Classes**: Implement mock versions of `Host`, `Network`, `P2PStream`, etc. These mocks should implement the interfaces from `dart_libp2p` but have simplified, in-memory behavior.

2.  **Create a Test Network Manager**: A central "manager" or "switch" class is needed to route messages between the mock networks of different peers. When `hostA` wants to open a stream to `hostB`, the manager creates a pair of connected in-memory streams and delivers them to the correct handlers.

    ```dart
    // From message_propagation_test.dart
    class TestNetworkManager {
      final Map<PeerId, MockNetwork> _networks = {};
      // ...
      Future<P2PStream> newStream(PeerId local, PeerId remote, ...) {
        // ... logic to connect two mock streams ...
      }
    }
    ```

3.  **Inject Mocks**: Create your `PubSub` instance using a `MockHost`.

    ```dart
    final (hostA, psA, routerA) = await createNode(networkManager);
    final (hostB, psB, routerB) = await createNode(networkManager);
    ```
    The `createNode` helper in this test sets up a `MockHost` and registers its `MockNetwork` with the `TestNetworkManager`.

4.  **Simulate Connections**: Instead of real network connections, you "connect" peers by adding them to each other's routers directly.

    ```dart
    await routerA.addPeer(hostB.id, gossipSubIDv11);
    await routerB.addPeer(hostA.id, gossipSubIDv11);
    ```

5.  **Perform Actions and Assert**: The rest of the test is similar to the integration test, but it runs much faster and more deterministically because the network is simulated.

**When to use this approach**: For unit or component tests of your application logic that sits on top of PubSub, or for testing specific scenarios within GossipSub itself without network flakiness.

---

By combining these two testing strategies, you can build a robust test suite that gives you confidence in your application's correctness and stability.

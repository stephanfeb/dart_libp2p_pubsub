# dart-libp2p-pubsub Developer Documentation

Welcome to the developer documentation for `dart-libp2p-pubsub`, a Dart implementation of the libp2p publish-subscribe pattern, with a focus on the GossipSub protocol.

## What is PubSub?

PubSub (Publish-Subscribe) is a messaging pattern where senders of messages, called publishers, do not program the messages to be sent directly to specific receivers, called subscribers. Instead, publishers categorize published messages into topics without knowledge of which subscribers, if any, there may be. Similarly, subscribers express interest in one or more topics and only receive messages that are of interest, without knowledge of which publishers, if any, there are.

## GossipSub: The Heart of the System

This library provides a `GossipSubRouter`, an implementation of the GossipSub protocol. GossipSub is a peer-to-peer pubsub protocol designed for scalability, resilience, and security. It builds a mesh network for each topic, ensuring that messages are efficiently propagated to all interested peers without flooding the entire network.

## About This Documentation

This documentation is designed to help you understand and effectively use `dart-libp2p-pubsub` in your applications. It is sourced from the library's core API and its integration tests to provide both conceptual knowledge and practical, real-world examples.

### Documentation Structure

1.  **[Setting Up a Libp2p Node](./1_network_setup.md)**: Learn how to configure a full libp2p network stack, which is the foundation for any PubSub application.
2.  **[Basic Pub/Sub Operations](./2_gossipsub_usage.md)**: A step-by-step guide to the most common operations: creating a PubSub instance, subscribing to topics, publishing messages, and receiving them.
3.  **[GossipSub Deep Dive](./3_gossipsub_deep_dive.md)**: Explore the advanced concepts of the GossipSub protocol, including the mesh network, heartbeats, and message caching.
4.  **[Testing Your Application](./4_testing.md)**: Discover strategies for testing your PubSub-enabled applications, including both full integration tests and isolated unit tests with mocks.
5.  **[Configuration and Tuning](./5_configuration.md)**: Learn how to configure and tune GossipSub parameters for optimal performance.
6.  **[Best Practices and Common Pitfalls](./6_best_practices.md)**: Read about best practices and common pitfalls to avoid when building your application.

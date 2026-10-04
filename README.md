# dart_libp2p_pubsub

A comprehensive libp2p pubsub implementation for Dart, featuring GossipSub v1.1, FloodSub, and RandomSub protocols with message validation, peer scoring, and tracing support.

[![Pub Version](https://img.shields.io/pub/v/dart_libp2p_pubsub)](https://pub.dev/packages/dart_libp2p_pubsub)
[![Dart CI](https://github.com/stephanfeb/dart_libp2p_pubsub/actions/workflows/dart.yml/badge.svg)](https://github.com/stephanfeb/dart_libp2p_pubsub/actions/workflows/dart.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

🚀 **Multiple PubSub Protocols**
- **GossipSub v1.1** - Production-ready, efficient pubsub protocol with mesh-based routing
- **FloodSub** - Simple flooding protocol for development and testing
- **RandomSub** - Randomized message propagation for research

🔒 **Security & Validation**
- Message validation with custom validators
- Peer scoring system for network health
- Cryptographic message signing and verification

📊 **Monitoring & Debugging**
- Comprehensive event tracing
- JSON and Protocol Buffer trace formats
- Built-in logging and metrics

⚡ **Performance**
- Efficient message caching with MCache
- Optimized RPC queue management
- Configurable mesh parameters for different use cases

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_libp2p_pubsub: ^1.4.1
  dart_libp2p: ^0.5.2
```

### Basic Usage

```dart
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p/core/host/host.dart';

// Create a libp2p host
final host = await createLibp2pHost();

// Set up GossipSub router
final router = GossipSubRouter();
// Published messages are signed with the host's own private key; no key
// needs to be passed.
final pubsub = PubSub(host, router);

// Start the pubsub system
await pubsub.start();

// Subscribe to a topic
const topic = '/my-app/chat';
final subscription = pubsub.subscribe(topic);

// Listen for messages
subscription.stream.listen((message) {
  print('Received: ${String.fromCharCodes(message.data)}');
});

// Publish a message
final messageData = Uint8List.fromList('Hello, World!'.codeUnits);
await pubsub.publish(topic, messageData);
```

## Examples

### Chat Application

Run a simple peer-to-peer chat:

```bash
# Terminal 1
dart example/chat.dart

# Terminal 2 (connect to the first node)
dart example/chat.dart /ip4/127.0.0.1/tcp/4001/p2p/QmPeerId...
```

### Custom Message Validation

```dart
// Define a custom validator
bool validateChatMessage(String topic, dynamic message) {
  if (topic != '/chat/1.0.0') return false;
  
  final data = String.fromCharCodes(message.data);
  return data.length <= 1000; // Max 1000 characters
}

// Register the validator
pubsub.addValidator('/chat/1.0.0', validateChatMessage);
```

### Peer Scoring

```dart
// Configure peer scoring parameters
final scoreParams = PeerScoreParams(
  behaviourPenaltyWeight: -10.0,
  behaviourPenaltyDecay: 0.99,
  behaviourPenaltyThreshold: -100.0,
);

final pubsub = PubSub(host, router, scoreParams: scoreParams);
```

## Documentation

📚 **Comprehensive Guides**
- [Network Setup](docs/1_network_setup.md) - Getting your libp2p network running
- [GossipSub Usage](docs/2_gossipsub_usage.md) - How to use GossipSub effectively
- [GossipSub Deep Dive](docs/3_gossipsub_deep_dive.md) - Advanced GossipSub concepts
- [Testing](docs/4_testing.md) - Testing strategies and examples
- [Configuration](docs/5_configuration.md) - Tuning parameters for your use case
- [Best Practices](docs/6_best_practices.md) - Production deployment guidelines

## Architecture

The library is organized into several key components:

```
lib/
├── src/
│   ├── core/           # Core pubsub functionality
│   │   ├── pubsub.dart      # Main PubSub class
│   │   ├── message.dart     # Message handling
│   │   ├── subscription.dart # Topic subscriptions
│   │   └── validation.dart  # Message validation
│   ├── gossipsub/      # GossipSub v1.1 implementation
│   │   ├── gossipsub.dart   # Main router
│   │   ├── mcache.dart      # Message cache
│   │   └── score.dart       # Peer scoring
│   ├── floodsub/       # FloodSub protocol
│   ├── randomsub/      # RandomSub protocol
│   └── tracing/        # Event tracing
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/stephanfeb/dart_libp2p_pubsub.git
cd dart_libp2p_pubsub

# Install dependencies
dart pub get

# Run tests
dart test

# Generate protobuf files
dart run build_runner build
```

A fresh clone builds against the published packages. To develop against local
checkouts of [dart_libp2p](https://github.com/stephanfeb/dart_libp2p),
[dart_libp2p_kad_dht](https://github.com/stephanfeb/dart_libp2p_kad_dht) or
[dart-udx](https://github.com/stephanfeb/dart-udx), create a
`pubspec_overrides.yaml` (git-ignored) next to `pubspec.yaml`:

```yaml
dependency_overrides:
  dart_libp2p:
    path: ../dart-libp2p
  dart_libp2p_kad_dht:
    path: ../dart-libp2p-kad-dht
  dart_udx:
    path: ../dart-udx
```

The Go interop test in `test/interop` builds the go-libp2p peer from a
dart_libp2p checkout (`GO_PEER_DIR`, or `../dart-libp2p/interop/go-peer` by
default) and needs Go.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Projects

- [dart_libp2p](https://pub.dev/packages/dart_libp2p) - Core libp2p implementation for Dart
- [dart_libp2p_kad_dht](https://pub.dev/packages/dart_libp2p_kad_dht) - Kademlia DHT implementation

## Support

- 📖 [Documentation](doc/)
- 🐛 [Issue Tracker](https://github.com/stephanfeb/dart_libp2p_pubsub/issues)
- 💬 [Discussions](https://github.com/stephanfeb/dart_libp2p_pubsub/discussions)

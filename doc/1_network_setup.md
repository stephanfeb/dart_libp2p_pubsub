# 1. Setting Up a Libp2p Node

Before you can use PubSub, you need a fully functional libp2p host. The host is the central component of a libp2p application, managing the peer's identity, connections, streams, and protocols.

This guide walks you through setting up a real network stack, using the configuration from `test/real_net_stack.dart` as a reference. This setup is suitable for building robust, production-ready applications.

## Core Components of a Libp2p Host

A libp2p host is composed of several key components that work together:

-   **Identity**: A `KeyPair` and the derived `PeerId`.
-   **Peerstore**: A database to store information about other peers (addresses, keys, protocols).
-   **Transport**: The underlying protocol for moving data between peers (e.g., TCP, UDX).
-   **Security Protocol**: A protocol to secure the communication channel (e.g., Noise).
-   **Stream Muxer**: A protocol to multiplex multiple independent streams over a single connection (e.g., Yamux).
-   **Swarm**: The network-layer component that manages connections and transports.
-   **Host**: The application-layer component that developers interact with.

## Step-by-Step Node Creation

Let's break down the process of creating a libp2p node. The following steps are based on the `createLibp2pNode` function in `test/real_net_stack.dart`.

### 1. Generate an Identity

Every peer in the libp2p network is identified by a `PeerId`, which is derived from its public key.

```dart
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/peer/peer_id.dart' as core_peer_id_lib;

// Generate a new Ed25519 key pair
final keyPair = await crypto_ed25519.generateEd25519KeyPair();

// Derive the PeerId from the public key
final peerId = await core_peer_id_lib.PeerId.fromPublicKey(keyPair.publicKey);
```

### 2. Configure the Peerstore

The `Peerstore` stores metadata about peers. The `MemoryPeerstore` is a simple in-memory implementation suitable for most cases. It's crucial to add the local peer's own keys to its peerstore.

```dart
import 'package:dart_libp2p/p2p/host/peerstore/pstoremem.dart';

final peerstore = MemoryPeerstore();
peerstore.keyBook.addPrivKey(peerId, keyPair.privateKey);
peerstore.keyBook.addPubKey(peerId, keyPair.publicKey);
```

### 3. Configure Transports, Security, and Muxers

These components define how your node will communicate.

-   **Transport**: We'll use `UDXTransport`, which is built on the UDX protocol for fast, reliable communication over UDP.
-   **Security**: We'll use `NoiseSecurity` for establishing an encrypted and authenticated session.
-   **Muxer**: We'll use `Yamux` for stream multiplexing.

```dart
import 'package:dart_libp2p/p2p/transport/udx_transport.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/multiplexing/yamux/session.dart';
import 'package:dart_libp2p/config/stream_muxer.dart';

// UDX Transport requires a ConnectionManager and a UDX instance
final connManager = p2p_transport.ConnectionManager();
final udxInstance = UDX();
final transport = UDXTransport(connManager: connManager, udxInstance: udxInstance);

// Noise Security Protocol requires the local peer's key pair
final securityProtocols = [await NoiseSecurity.create(keyPair)];

// Yamux Stream Muxer configuration
final yamuxConfig = MultiplexerConfig(/* ... */);
final muxerDefs = [
  _TestYamuxMuxerProvider(yamuxConfig: yamuxConfig) // A helper class providing the factory
];
```

### 4. Create the Swarm (Network Layer)

The `Swarm` is the core of the networking stack. It takes the transport, peerstore, and configurations, and manages all connections and substreams.

```dart
import 'package:dart_libp2p/p2p/network/swarm/swarm.dart';
import 'package:dart_libp2p/config/config.dart' as p2p_config;

final swarmConfig = p2p_config.Config()
  ..peerKey = keyPair
  ..securityProtocols = securityProtocols
  ..muxers = muxerDefs
  // ... other settings like connection manager, event bus, etc.

final network = Swarm(
  localPeer: peerId,
  peerstore: peerstore,
  upgrader: BasicUpgrader(/* ... */), // Upgrader uses security and muxers
  config: swarmConfig,
  transports: [transport],
  resourceManager: NullResourceManager(), // Use an appropriate resource manager
);
```

### 5. Create the BasicHost (Application Layer)

The `BasicHost` is the primary interface for developers. It sits on top of the `Swarm` and provides a clean API for connecting to peers, opening streams, and registering protocol handlers.

```dart
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';

final hostConfig = p2p_config.Config()
  ..peerKey = keyPair
  // ... other settings like event bus, user agent, etc.

final host = await BasicHost.create(
  network: network,
  config: hostConfig,
);

// It's important to link the Swarm back to its Host
network.setHost(host);
```

### 6. Start the Host and Listen

Finally, start the host and tell it to listen on one or more multiaddresses.

```dart
// Start the host and its underlying network swarm
await host.start();

// Define listen addresses
final listenAddrs = [MultiAddr('/ip4/0.0.0.0/udp/0/udx')];

// Start listening for incoming connections
await network.listen(listenAddrs);

print('Host ${peerId.toBase58()} is listening on: ${host.addrs}');
```

With these steps, you have a fully operational libp2p node. This `host` object is the foundation you will build upon to use PubSub, as you will see in the next section.

---

**Next**: [2. Basic Pub/Sub Operations](./2_gossipsub_usage.md)

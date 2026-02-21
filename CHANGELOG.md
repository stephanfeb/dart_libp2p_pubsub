# Changelog

All notable changes to this project will be documented in this file.

## 1.2.0 - 2026-02-21

### Changed
- Router `handleRpc` now returns accepted message IDs (`Set<String>`) so PubSub only delivers messages the router actually accepted, preventing double-delivery
- Signature verification strictly requires an embedded public key (reject messages without one)

### Fixed
- FloodSub and RandomSub double-delivery of messages to local subscribers
- GossipSub publish to topics without mesh peers now builds fanout from known subscribed peers
- Test mocks updated to match new Router interface and Network requirements

## 1.1.0 - 2026-02-17

### Added
- Go-libp2p GossipSub interop compatibility
- Strict signature validation with key-PeerId consistency check
- IdentifyTimeoutException handling to prevent crashes
- Stream re-use for RPC message sending
- Connection protection for critical peers

### Fixed
- Test failures in gossipsub and validation tests
- Network errors crashing host app

### Changed
- Updated `dart_libp2p` dependency to `^1.0.0`
- Updated `dart_libp2p_kad_dht` dependency to `^1.2.0`
- Updated `dart_udx` dependency to `^2.0.1`

## 1.0.1

### Features

#### Core PubSub System
- **Complete PubSub Implementation**: Full publish-subscribe pattern with topic-based messaging
- **Message Handling**: Robust message routing, delivery, and subscription management
- **Topic Management**: Dynamic topic creation, subscription, and unsubscription
- **Message Validation**: Custom validator support for topic-specific message validation
- **Peer Management**: Comprehensive peer discovery, connection, and lifecycle management

#### Multiple PubSub Protocols
- **GossipSub v1.1**: Production-ready mesh-based pubsub protocol with efficient message propagation
  - Two-tiered network structure (mesh + gossip network)
  - Dynamic mesh maintenance with GRAFT/PRUNE control messages
  - Heartbeat-based network health monitoring
  - Message caching (MCache) for deduplication and IHAVE/IWANT support
  - Configurable mesh parameters (D, DLow, DHigh, DScore)
  - Fanout management for non-subscribed topic publishing
  - Opportunistic grafting for mesh strengthening
  - Peer Exchange (PX) mechanism for network connectivity

- **FloodSub**: Simple flooding protocol for development and testing
- **RandomSub**: Randomized message propagation for research and experimentation

#### Security & Network Health
- **Peer Scoring System**: Comprehensive scoring mechanism to protect against malicious behavior
  - Behavior-based scoring with configurable parameters
  - Automatic peer blacklisting for misbehaving nodes
  - Score decay and threshold management
  - Opportunistic grafting based on peer scores

- **Message Validation**: Topic-specific message validation with custom validators
- **Cryptographic Support**: Message signing and verification capabilities

#### Monitoring & Debugging
- **Event Tracing**: Comprehensive tracing system for debugging and monitoring
  - JSON tracer for human-readable trace output
  - Protocol Buffer tracer for efficient binary trace format
  - Trace event types for different pubsub operations
  - Configurable tracing levels and output formats

- **Built-in Logging**: Integrated logging system with configurable levels
- **Metrics Support**: Performance and network health metrics

#### Performance & Optimization
- **Message Caching**: Efficient MCache implementation for message deduplication
- **RPC Queue Management**: Optimized outgoing RPC queue management
- **Configurable Parameters**: Extensive configuration options for different use cases
  - Mesh size control (D, DLow, DHigh)
  - Gossip propagation settings (DLazy)
  - Fanout TTL configuration
  - Peer scoring thresholds
  - Prune and Peer Exchange settings

#### Developer Experience
- **Comprehensive Documentation**: Complete documentation suite covering:
  - Network setup and configuration
  - Basic pub/sub operations
  - GossipSub deep dive and advanced concepts
  - Testing strategies and examples
  - Configuration and tuning guidelines
  - Best practices and common pitfalls

- **Example Applications**: Working chat application demonstrating real-world usage
- **Integration Tests**: Comprehensive test suite with real network integration
- **Mock Support**: Mockito-based testing support for isolated unit tests

### Technical Implementation
- **Protocol Buffer Support**: Full protobuf integration for RPC messages and tracing
- **Async/Await Support**: Modern Dart async programming patterns throughout
- **Stream-based API**: Reactive programming with Dart streams for message handling
- **Resource Management**: Proper cleanup and resource management
- **Error Handling**: Comprehensive error handling and recovery mechanisms

### Dependencies
- **dart_libp2p**: Core libp2p networking stack integration
- **dart_libp2p_kad_dht**: Kademlia DHT support for peer discovery
- **dcid**: Content identifier support
- **Cryptography**: Advanced cryptographic operations
- **Protobuf**: Protocol buffer serialization
- **Logging**: Structured logging support

## 1.0.0

- Initial version.

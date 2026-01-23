import 'package:dart_libp2p/core/connmgr/conn_manager.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/network/network.dart';
import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peerstore.dart';
import 'package:dart_libp2p/core/protocol/switch.dart';
import 'package:dart_libp2p/p2p/protocol/holepunch/holepunch_service.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/host/host.dart'; // StreamHandler is here
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/keys.dart'; // Added for KeyPair
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519; // Added for key generation
import 'package:dart_libp2p/core/event/bus.dart' as event_bus; // Prefixed
import 'package:dart_libp2p/core/network/stream.dart';
// import 'package:dart_libp2p/core/network/network.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_network_context;
// import 'package:dart_libp2p/core/peerstore.dart';
// import 'package:dart_libp2p/core/connection_manager.dart';
// import 'package:dart_libp2p/core/multiaddress.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart'; // For AddrInfo, assuming this path is correct
// import 'package:dart_libp2p/core/protocol/holepunch/holepunch.dart';


import '../../lib/src/core/pubsub.dart';
// Removed typedef MockStreamHandler as it's unused and StreamHandler should come from host.dart
import '../../lib/src/core/message.dart'; // Added for PubSubMessage
import '../../lib/src/core/router.dart';
import '../../lib/src/core/subscription.dart';
import '../../lib/src/core/topic.dart'; // Added for Topic
import '../../lib/src/gossipsub/gossipsub.dart';


// --- Mock Implementations ---

// Minimal P2PStream mock
class MockP2PStream implements P2PStream {
  @override
  Future<void> close() async {}

  @override
  Future<void> closeRead() async {}

  @override
  Future<void> closeWrite() async {}

  @override
  String id() { return 'mock-stream-id'; } // Changed to method

  @override
  Stream<Uint8List> get stream => Stream.value(Uint8List(0));

  @override
  StreamSink<List<int>> get sink => _MockStreamSink();

  @override
  Future<void> reset() async {}

  @override
  String protocol() { return '/mock/protocol/1.0.0'; } // Changed to method
  
  @override
  Future<void> get writeClosed => Future.value();

  // Implementing missing P2PStream methods
  @override
  Future<Uint8List> read([int? count]) async => Uint8List(0);


  @override
  Future<void> setDeadline(DateTime? time) async {}

  @override
  Future<void> setProtocol(String proto) async {} // Corrected signature (async)

  @override
  Future<int> write(Uint8List data) async => data.length;
  
  @override
  Future<void> get readClosed => Future.value();
  
  @override
  bool get isClosed => false;
  
  @override
  bool get isReadClosed => false;
  
  @override
  bool get isWriteClosed => false;

  // Added stubs for other P2PStream methods
  @override
  Future<void> setReadDeadline(DateTime? time) async {}

  @override
  Future<void> setWriteDeadline(DateTime? time) async {}

  @override
  // TODO: implement conn
  Conn get conn => throw UnimplementedError();

  @override
  // TODO: implement incoming
  P2PStream<Uint8List> get incoming => throw UnimplementedError();

  @override
  StreamManagementScope scope() {
    // TODO: implement scope
    throw UnimplementedError();
  }

  @override
  StreamStats stat() {
    // TODO: implement stat
    throw UnimplementedError();
  }

  @override
  // TODO: implement isWritable
  bool get isWritable => throw UnimplementedError();
}

class _MockStreamSink implements StreamSink<List<int>> {
  @override
  void add(List<int> event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done => Future.value();
}


class MockHost implements Host {
  late final PeerId _peerId;
  late final KeyPair _keyPair;

  KeyPair get keyPair => _keyPair; // Store keypair for potential future use in mock

  // Asynchronous initialization block for _peerId and _keyPair
  // This is tricky for a constructor. We'll make `create` static async factory.
  MockHost._internal(this._peerId, this._keyPair);

  static Future<MockHost> create() async {
    final keyPair = await crypto_ed25519.generateEd25519KeyPair();
    final peerId = await PeerId.fromPublicKey(keyPair.publicKey);
    return MockHost._internal(peerId, keyPair);
  }

  @override
  PeerId get id => _peerId;

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}

  @override
  void setStreamHandler(String protocol, Future<void> Function(P2PStream stream, PeerId remotePeer) handler) {
    print('MockHost: setStreamHandler for $protocol with specific handler signature');
  }

  @override
  void removeStreamHandler(String protocol) {
    print('MockHost: removeStreamHandler for $protocol');
  }

  @override
  Future<P2PStream> newStream(PeerId peerId, List<String> protocols, [core_network_context.Context? ctx]) async {
    print('MockHost: newStream to $peerId for $protocols');
    return MockP2PStream();
  }

  @override
  Future<void> close() async {
    print('MockHost: close');
  }

  @override
  Future<void> connect(AddrInfo addrInfo, {core_network_context.Context? context}) async {
    print('MockHost: connect to ${addrInfo.id} via ${addrInfo.addrs}');
  }

  @override
  void setStreamHandlerMatch(String protocol, bool Function(String) matcher, Future<void> Function(P2PStream stream, PeerId remotePeer) handler) {
    print('MockHost: setStreamHandlerMatch for $protocol with specific handler signature');
  }

  @override
  // TODO: implement addrs
  List<MultiAddr> get addrs => throw UnimplementedError();

  @override
  // TODO: implement connManager
  ConnManager get connManager => throw UnimplementedError();

  @override
  // TODO: implement eventBus
  event_bus.EventBus get eventBus => throw UnimplementedError();

  @override
  // TODO: implement holePunchService
  HolePunchService? get holePunchService => throw UnimplementedError();

  @override
  // TODO: implement mux
  ProtocolSwitch get mux => throw UnimplementedError();

  @override
  // TODO: implement network
  Network get network => throw UnimplementedError();

  @override
  // TODO: implement peerStore
  Peerstore get peerStore => throw UnimplementedError();

}

// Removed _MockPeerStore and _MockConnectionManager to simplify and reduce errors.
// PubSub core tests might not need full implementations of these.

// A simple mock Router
class MockRouter implements Router {
  PubSub? attachedPubSub;
  List<String> joinedTopics = [];
  List<PubSubMessage> publishedMessages = [];

  @override
  Future<void> attach(PubSub pubsub) async {
    attachedPubSub = pubsub;
    print('MockRouter: Attached to PubSub');
  }
  @override
  Future<void> detach() async {
    print('MockRouter: Detached');
  }
  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {}
  @override
  Future<void> removePeer(PeerId peerId) async {}
  @override
  Future<void> handleRpc(PeerId peerId, dynamic rpc) async {} // Typed rpc
  
  @override
  Future<void> publish(PubSubMessage message) async { // Typed message
    publishedMessages.add(message);
    print('MockRouter: publish called for message on topic ${message.topic}'); // Reverted to .topic
  }
  @override
  Future<void> join(Topic topic) async { // Typed topic
    joinedTopics.add(topic.name);
    print('MockRouter: join called for topic ${topic.name}');
  }
  @override
  Future<void> leave(Topic topic) async { // Typed topic
    joinedTopics.remove(topic.name);
    print('MockRouter: leave called for topic ${topic.name}');
  }
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}


void main() {
  group('PubSub Core Logic Tests', () {
    late MockHost mockHost; // Keep as Host type
    late Router mockRouter;
    late PubSub pubsub;

    setUp(() async { // setUp needs to be async now
      mockHost = await MockHost.create(); // Use the async factory
      mockRouter = MockRouter();
      // Initialize PubSub with mocks
      // Assuming PubSub constructor takes Host and Router
      pubsub = PubSub(mockHost, mockRouter, privateKey: mockHost.keyPair.privateKey);
    });

    test('should allow subscription to a topic', () {
      final topic = 'test-topic';
      final subscription = pubsub.subscribe(topic);
      expect(subscription, isA<Subscription>());
      expect(subscription.topic, equals(topic));
      expect(pubsub.getTopics(), contains(topic));
    });

    test('subscription stream should receive published messages', () async {
      final topic = 'test-topic';
      final data = Uint8List.fromList([1, 2, 3]);
      
      final subscription = pubsub.subscribe(topic);
      
      // Expect one message on the stream
      final futureMessage = subscription.stream.first;
            
      await pubsub.publish(topic, data);
            
      final receivedMsg = await futureMessage.timeout(Duration(seconds: 1));
      
      expect(receivedMsg, isA<PubSubMessage>());
      expect(receivedMsg.topic, topic); // Reverted to .topic
      expect(receivedMsg.data, equals(data));
    });

    test('unsubscribe should remove subscription', () async {
      final topic = 'test-topic';
      final subscription = pubsub.subscribe(topic);
      expect(pubsub.getTopics(), contains(topic));
      
      await subscription.cancel(); // Subscription.cancel calls the callback in PubSub
      expect(pubsub.getTopics(), isNot(contains(topic)));
    });

    test('unsubscribeAll should remove all subscriptions for a topic', () async {
      final topic = 'test-topic';
      final sub1 = pubsub.subscribe(topic);
      final sub2 = pubsub.subscribe(topic);
      expect(pubsub.getTopics(), contains(topic));
      
      await pubsub.unsubscribe(topic); // This calls cancel on all subscriptions for the topic
      expect(pubsub.getTopics(), isNot(contains(topic)));
      expect(sub1.isCancelled, isTrue);
      expect(sub2.isCancelled, isTrue);
    });

    // TODO: Add tests for message validation registration and invocation.
    // TODO: Add tests for publish with validation failure.
    // TODO: Add tests for tracer integration (how to verify trace calls).
  });
}

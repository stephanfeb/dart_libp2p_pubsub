import 'dart:async';
import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/pubsub.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/gossipsub.dart';
import 'package:dart_libp2p_pubsub/src/core/message.dart';
import 'package:dart_libp2p_pubsub/src/core/subscription.dart';
import 'package:dart_libp2p_pubsub/src/core/topic.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as rpc;
import 'package:dart_libp2p_pubsub/src/core/comm.dart'; // For gossipSubIDv11

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/network.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/network/context.dart';
import 'package:dart_libp2p/core/network/notifiee.dart';
import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peerstore.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/protocol/protocol.dart';
import 'package:dart_libp2p/core/protocol/switch.dart';
import 'package:dart_libp2p/core/connmgr/conn_manager.dart';
import 'package:dart_libp2p/core/event/bus.dart' hide Subscription;
import 'package:dart_libp2p/p2p/protocol/holepunch.dart';
import 'package:dart_libp2p/p2p/discovery/peer_info.dart';
import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/common.dart'; // For Direction
import 'dart:typed_data';
import 'package:fixnum/fixnum.dart';

// Helper function to create a new PubSub node setup
Future<(MockHost, PubSub, GossipSubRouter)> createNode(TestNetworkManager manager) async {
  final keyPair = await generateEd25519KeyPair();
  final peerId = PeerId.fromPublicKey(keyPair.publicKey);
  final host = MockHost(peerId, keyPair.privateKey);
  
  // Set manager on MockNetwork and register with the manager BEFORE PubSub initialization
  (host.network as MockNetwork).manager = manager;
  manager.registerNetwork(peerId, host.network as MockNetwork);

  final router = GossipSubRouter();
  final pubsub = PubSub(host, router); // Now PubSubProtocol will register its handler correctly
  await pubsub.start();
  await router.start(); 
  return (host, pubsub, router);
}

// Centralized "Network Switch" to connect MockNetwork instances
class TestNetworkManager {
  final Map<PeerId, MockNetwork> _networks = {};
  final Map<PeerId, Map<String, Future<void> Function(P2PStream stream, PeerId remotePeer)>> _protocolHandlers = {};


  void registerNetwork(PeerId peerId, MockNetwork network) {
    _networks[peerId] = network;
    _protocolHandlers[peerId] = {};
    network.manager = this; // Allow MockNetwork to call back to manager
  }

  void unregisterNetwork(PeerId peerId) {
    _networks.remove(peerId);
    _protocolHandlers.remove(peerId);
  }
  
  void setHandler(PeerId localPeerId, String protocol, Future<void> Function(P2PStream stream, PeerId remotePeer) handler) {
    _protocolHandlers[localPeerId]?[protocol] = handler;
  }

  // Simulates opening a new stream from localPeer to remotePeer for given protocols
  Future<P2PStream> newStream(PeerId localPeerId, PeerId remotePeerId, List<ProtocolID> protocols) async {
    final remoteNetwork = _networks[remotePeerId];
    if (remoteNetwork == null) {
      throw Exception('Remote peer $remotePeerId not found in TestNetworkManager');
    }

    // For PubSub, the primary protocol is GossipSub (or FloodSub, etc.)
    // The PubSubProtocol class in comm.dart handles RPCs over this stream.
    // We need to find a handler for one of the requested protocols on the remote peer.
    String? matchedProtocol;
    Future<void> Function(P2PStream stream, PeerId remotePeer)? handler;

    for (var protoId in protocols) {
      final protoStr = protoId.toString(); // Assuming ProtocolID can be converted to string key
      if (_protocolHandlers[remotePeerId]?.containsKey(protoStr) ?? false) {
        handler = _protocolHandlers[remotePeerId]![protoStr];
        matchedProtocol = protoStr;
        break;
      }
    }
    
    if (handler == null || matchedProtocol == null) {
      throw Exception('No handler for protocols ${protocols.map((p) => p.toString()).join(', ')} on peer $remotePeerId');
    }

    // Create two ends of a pipe-like stream
    final controller1 = StreamController<Uint8List>();
    final controller2 = StreamController<Uint8List>();

    final stream1 = MockP2PStream(remotePeerId, matchedProtocol, controller1, controller2.sink);
    final stream2 = MockP2PStream(localPeerId, matchedProtocol, controller2, controller1.sink);
    
    // Immediately invoke the handler on the remote peer with its end of the stream
    // Run in a microtask to avoid re-entrancy issues if handler is synchronous
    Future.microtask(() => handler!(stream2, localPeerId));
    
    // Return the local peer's end of the stream
    return stream1;
  }
}


void main() {
  group('Message Propagation Tests', () {
    late TestNetworkManager networkManager;

    setUp(() {
      networkManager = TestNetworkManager();
    });

    test('Message published by one node is received by a subscribed peer', () async {
      final (hostA, psA, routerA) = await createNode(networkManager);
      final (hostB, psB, routerB) = await createNode(networkManager);
      
      // Networks are now registered within createNode

      // Simulate A and B "connecting" or knowing about each other.
      // In a real scenario, this involves discovery and dialing.
      // For GossipSub, peers need to be added to the router.
      // PubSub's _handleRpc is set up by PubSubProtocol, which is initialized in PubSub constructor.
      // The PubSubProtocol registers itself with the Host for the GossipSub protocol ID.
      // So, when MockHost.newStream is called by PubSub A to send to B,
      // TestNetworkManager should route it to PubSub B's handler.

      // Let's assume direct "connection" for now by adding peers to each other's routers
      // This simulates the outcome of a connection and protocol negotiation.
      // The PubSub layer in comm.dart uses host.setStreamHandler to listen for incoming streams.
      // Our MockHost needs to correctly forward setStreamHandler calls to TestNetworkManager.
      
      // Also, PubSub.addPeer is called by the router when it learns of a new peer.
      // For GossipSub, this might happen after a GRAFT or when a connection is established.
      // We need to ensure routers are aware of each other to form a mesh.
      
      // Manually add peers to each other's PubSub instances (which informs the router)
      // This would typically happen via discovery and connection events.
      await routerA.addPeer(hostB.id, gossipSubIDv11);
      await routerB.addPeer(hostA.id, gossipSubIDv11);


      const topicName = 'test-prop-topic';

      final subB = psB.subscribe(topicName);
      final topicObjA = Topic(topicName);
      await routerA.join(topicObjA); // Node A joins the topic mesh
      
      final topicObjB = Topic(topicName); // Node B also joins
      await routerB.join(topicObjB);


      Completer<PubSubMessage> receivedMessageCompleter = Completer();
      subB.stream.listen((message) {
        if (!receivedMessageCompleter.isCompleted) {
          receivedMessageCompleter.complete(message);
        }
      });

      final testData = Uint8List.fromList([10, 20, 30, 40]);
      await psA.publish(topicName, testData);

      final receivedMessage = await receivedMessageCompleter.future.timeout(Duration(seconds: 5));
      
      expect(receivedMessage.data, equals(testData));
      expect(receivedMessage.from, equals(hostA.id)); // In PubSubMessage, 'from' is the original publisher
      expect(receivedMessage.receivedFrom, equals(hostA.id)); // For direct message from publisher via router
      // If message came via another peer, receivedFrom would be that peer.
      // In this simple 2-node test, it should be hostA.
      
      // Cleanup
      await psA.stop();
      await psB.stop();
    });
  });
}

// --- Mock Classes (Copied and will be enhanced) ---
class MockP2PStream implements P2PStream<Uint8List> {
  final PeerId _remotePeer;
  String _protocolValue;
  // Removed duplicate final PeerId _remotePeer;
  // Removed duplicate String _protocolValue;
  final StreamController<Uint8List> _readController;
  final StreamSink<Uint8List> _writeSink; // Changed type to StreamSink
  bool _selfClosed = false; // Indicates if close() was called on this MockP2PStream instance
  DateTime _openedAt = DateTime.now();

  MockP2PStream(this._remotePeer, this._protocolValue, this._readController, StreamSink<Uint8List> writeSink) : _writeSink = writeSink;

  @override
  String id() => '${_remotePeer.toBase58()}-${_protocolValue}-${_openedAt.microsecondsSinceEpoch}';

  @override
  String protocol() => _protocolValue;

  @override
  Future<void> setProtocol(String id) async {
    _protocolValue = id;
  }

  @override
  StreamStats stat() => StreamStats(
    direction: Direction.unknown, // Placeholder
    opened: _openedAt,
  );

  @override
  Conn get conn => throw UnimplementedError('MockP2PStream.conn not implemented');

  @override
  StreamManagementScope scope() => throw UnimplementedError('MockP2PStream.scope not implemented');
  
  @override
  Future<Uint8List> read([int? maxLength]) async {
    if (_readController.isClosed) {
      throw StateError('Stream is closed for reading');
    }
    return await _readController.stream.first;
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_selfClosed || _writeSinkDone) { // Check our own flag or if sink is done
       throw StateError('Stream is closed for writing');
    }
    _writeSink.add(data);
  }
  
  @override
  P2PStream<Uint8List> get incoming => this;

  // Helper to check if write sink is done
  bool get _writeSinkDone {
    // This is tricky. `StreamSink.done` is a future.
    // For a synchronous check, we'd need more state or rely on _selfClosed.
    // For now, primarily rely on _selfClosed.
    return _selfClosed; 
  }

  @override
  Future<void> close() async {
    if (_selfClosed) return;
    _selfClosed = true;
    if (!_readController.isClosed) {
      _readController.close(); // Don't await
    }
    try {
      _writeSink.close(); // Don't await
    } catch (e) {
      // Ignore errors
    }
    return Future.value(); // Return a completed future
  }
  
  @override
  Future<void> closeWrite() async {
    try {
      _writeSink.close(); // Don't await
    } catch (e) {
      // Ignore errors
    }
    return Future.value();
  }

  @override
  Future<void> closeRead() async {
     if (!_readController.isClosed) {
       _readController.close(); // Don't await
     }
     return Future.value();
  }
  
  @override
  Future<void> reset() async {
    _selfClosed = true;
    if (!_readController.isClosed) {
      _readController.addError(Exception('Stream reset'));
      _readController.close(); // Don't await
    }
    try {
      _writeSink.close(); // Don't await
    } catch (e) {
      // ignore
    }
    return Future.value();
  }

  @override
  Future<void> setDeadline(DateTime? time) async {
    // Mock deadline, not implemented
  }

  @override
  Future<void> setReadDeadline(DateTime time) async {
    // Mock deadline, not implemented
  }

  @override
  Future<void> setWriteDeadline(DateTime time) async {
    // Mock deadline, not implemented
  }
  
  @override
  bool get isClosed => _selfClosed || _readController.isClosed; // Simplified: if explicitly closed or read end is closed.
  
  // Expose remotePeer via a getter to match the old mock's public field, if needed by other parts of the mock setup.
  PeerId get remotePeer => _remotePeer;

  @override
  // TODO: implement isWritable
  bool get isWritable => throw UnimplementedError();
}

class MockNetwork implements Network, Dialer {
  final MockHost _host; // Changed from Host to MockHost for access to manager
  TestNetworkManager? manager; // Reference to the central manager

  MockNetwork(this._host);

  @override
  PeerId get localPeer => _host.id;

  @override
  Peerstore get peerstore => _host.peerStore;

  @override
  List<PeerId> get peers => manager?._networks.keys.where((id) => id != _host.id).toList() ?? [];

  @override
  Future<void> close() async {}

  @override
  Stream<Conn> get newConnections => Stream.empty();

  @override
  Future<Conn> dialPeer(Context context, PeerId peerId) async {
    // Simulate dialing: In a real scenario, this would establish a connection.
    // For mocks, we can assume connection if the peer is known to the manager.
    if (manager?._networks.containsKey(peerId) ?? false) {
      // Return a mock connection object.
      // This part needs a MockConn if methods on Conn are used.
      print('MockNetwork: Dialing ${peerId.toBase58()} successful (simulated).');
      // For now, let's assume this is enough for PubSub to proceed.
      // If PubSub tries to use the Conn, this will need to be a proper MockConn.
      throw UnimplementedError('MockNetwork.dialPeer needs to return a MockConn');
    }
    throw Exception('Failed to dial peer ${peerId.toBase58()}: Not found in TestNetworkManager');
  }

  @override
  Future<void> listen(List<MultiAddr> addrs) async {}

  @override
  void setStreamHandler(String protocol, Future<void> Function(P2PStream stream, PeerId remotePeer) handler) {
    // Delegate to TestNetworkManager
    manager?.setHandler(_host.id, protocol, handler);
  }

  @override
  List<Conn> get conns => [];
  
  @override
  List<Conn> connsToPeer(PeerId peerId) => [];

  @override
  Future<P2PStream> newStream(Context context, PeerId remotePeerId) async {
    // This newStream is from the Network interface, usually called by Host.newStream with specific protocols.
    // Host.newStream is: Future<P2PStream> newStream(PeerId p, List<ProtocolID> pids, Context context);
    // This method on Network doesn't take protocols. This seems like a mismatch or simplification in the mock.
    // For PubSub, it will call Host.newStream with the PubSub protocol.
    // So, this specific newStream on Network might not be directly used by PubSub's core logic if it always goes via Host.
    // Let's assume Host.newStream is the primary one used.
    // If this IS called, we need to know which protocol. For now, this is problematic.
    throw UnimplementedError('MockNetwork.newStream(Context, PeerId) called. Need protocols. Use Host.newStream.');
  }


  @override
  Connectedness connectedness(PeerId peerId) => 
    manager?._networks.containsKey(peerId) ?? false ? Connectedness.connected : Connectedness.notConnected;

  @override
  void notify(Notifiee notifiee) {}

  @override
  void stopNotify(Notifiee notifiee) {}

  @override
  Future<void> closePeer(PeerId peerId) async {}
  
  @override
  bool canDial(PeerId peerId, MultiAddr addr) => manager?._networks.containsKey(peerId) ?? false;

  @override
  List<MultiAddr> get listenAddresses => [];
  
  @override
  Future<List<MultiAddr>> get interfaceListenAddresses async => [];

  @override
  void removeListenAddress(MultiAddr addr) {}

  @override
  ResourceManager get resourceManager => throw UnimplementedError('MockNetwork.resourceManager not implemented');
}

class MockHost implements Host {
  @override
  final PeerId id;
  final PrivateKey _privateKey;
  late final MockNetwork _mockNetwork; 
  late final Peerstore _peerstore; 

  MockHost(this.id, this._privateKey) {
    _mockNetwork = MockNetwork(this);
    _peerstore = MockPeerstore();
  }

  @override
  Network get network => _mockNetwork;

  @override
  PrivateKey get privateKey => _privateKey;

  @override
  List<MultiAddr> get addrs => [];

  @override
  Peerstore get peerStore => _peerstore;

  @override
  Future<void> close() async {}

  @override
  Future<void> connect(AddrInfo pi, {Context? context}) async {
    // Simulate connection by ensuring the network manager knows about the peer.
    // This is a simplification. Real connection involves dialing.
    if (!(_mockNetwork.manager?._networks.containsKey(pi.id) ?? false)) {
       print('MockHost.connect: Peer ${pi.id.toBase58()} not in network manager, cannot connect.');
       // throw Exception('Cannot connect to peer not in network manager');
       // For tests, we might assume it "becomes" available if we try to connect.
       // Or, tests should ensure peers are registered with TestNetworkManager first.
    }
     print('MockHost.connect: Connecting to ${pi.id.toBase58()} (simulated).');
  }

  @override
  void setStreamHandler(ProtocolID pid, StreamHandler handler) {
    _mockNetwork.setStreamHandler(pid.toString(), handler);
  }

  @override
  void removeStreamHandler(ProtocolID pid) {}
  
  @override
  Future<P2PStream> newStream(PeerId p, List<ProtocolID> pids, Context context) async {
    if (_mockNetwork.manager == null) {
      throw Exception('TestNetworkManager not set for MockNetwork of host ${id.toBase58()}');
    }
    return _mockNetwork.manager!.newStream(id, p, pids);
  }
  
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  ProtocolSwitch get mux => throw UnimplementedError('MockHost.mux not implemented');

  @override
  void setStreamHandlerMatch(ProtocolID pid, bool Function(ProtocolID) match, StreamHandler handler) {
    throw UnimplementedError('MockHost.setStreamHandlerMatch not implemented');
  }

  @override
  ConnManager get connManager => throw UnimplementedError('MockHost.connManager not implemented');

  @override
  EventBus get eventBus => throw UnimplementedError('MockHost.eventBus not implemented');
  
  @override
  HolePunchService? get holePunchService => null;
}

class MockPeerstore implements Peerstore {
  @override
  AddrBook get addrBook => throw UnimplementedError('MockPeerstore.addrBook not implemented');
  @override
  Future<void> close() async {}
  @override
  KeyBook get keyBook => throw UnimplementedError('MockPeerstore.keyBook not implemented');
  @override
  Metrics get metrics => throw UnimplementedError('MockPeerstore.metrics not implemented');
  @override
  Future<AddrInfo> peerInfo(PeerId id) async => AddrInfo(id, []);
  @override
  Future<List<PeerId>> peers() async => [];
  @override
  PeerMetadata get peerMetadata => throw UnimplementedError('MockPeerstore.peerMetadata not implemented');
  @override
  ProtoBook get protoBook => throw UnimplementedError('MockPeerstore.protoBook not implemented');
  @override
  Future<void> removePeer(PeerId id) async {}
  @override
  Future<void> addOrUpdatePeer(PeerId peerId, {List<MultiAddr>? addrs, List<String>? protocols, Map<String, dynamic>? metadata}) async {}
  @override
  Future<PeerInfo?> getPeer(PeerId peerId) async => null;
}

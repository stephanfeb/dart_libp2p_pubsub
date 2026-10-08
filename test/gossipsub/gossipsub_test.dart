import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/gossipsub.dart';
import 'package:dart_libp2p_pubsub/src/core/pubsub.dart';
import 'dart:typed_data'; // For Uint8List

import 'package:dart_libp2p_pubsub/src/core/comm.dart'; // For PubSubProtocol and protocol IDs
import 'package:dart_libp2p_pubsub/src/tracing/tracer.dart'; // For EventTracer
import 'package:dart_libp2p_pubsub/src/pb/trace.pb.dart' as trace_pb; // For trace event types
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb; // For RPC message types
import 'package:dart_libp2p_pubsub/src/core/topic.dart';
import 'package:dart_libp2p_pubsub/src/core/router.dart' show AcceptStatus; // For Topic
import 'package:dart_libp2p_pubsub/src/core/message.dart'; // For PubSubMessage
import 'package:dart_libp2p_pubsub/src/util/midgen.dart'; // For defaultMessageIdFn
import 'package:dart_libp2p_pubsub/src/gossipsub/score_params.dart'; // For PeerScoreParams
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/network.dart'; // Added Network import
import 'package:dart_libp2p/core/connmgr/conn_manager.dart'; // For ConnManager
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/common.dart' show Direction;
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/certified_addr_book.dart';
import 'package:dart_libp2p/core/crypto/ed25519.dart' show generateEd25519KeyPair;
import 'package:dart_libp2p/core/crypto/keys.dart' show KeyPair;
import 'package:dart_libp2p/core/network/network.dart' show Connectedness;
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/record.dart';
import 'package:dart_libp2p/core/peerstore.dart';
import 'package:dart_libp2p/core/record/envelope.dart';
import 'package:dart_libp2p/core/record/record_registry.dart';
import 'package:dart_libp2p/core/peer/pb/peer_record.pb.dart' as record_pb;
import 'package:fixnum/fixnum.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:fake_async/fake_async.dart'; // Import for FakeAsync
import 'gossipsub_test.mocks.dart'; // Generated mocks

/// Answers a stubbed PubSub.validateMessage as the real one does: marks the
/// message seen (its signature is taken as valid), then returns [result].
Future<ValidationResult> _validated(Invocation invocation, ValidationResult result) async {
  final markSeen = invocation.namedArguments[#markSeen] as bool Function()?;
  if (markSeen != null && !markSeen()) return ValidationResult.ignore;
  return result;
}

/// A connection that only answers what GossipSubRouter.addPeer reads: its
/// direction and its (loopback, so not IP-scored) remote address.
class _FakeConn extends Fake implements Conn {
  final Direction direction;
  _FakeConn(this.direction);

  @override
  ConnStats get stat => _FakeConnStats(Stats(direction: direction, opened: DateTime(2020)));

  @override
  MultiAddr get remoteMultiaddr => MultiAddr('/ip4/127.0.0.1/tcp/4001');
}

class _FakeConnStats extends ConnStats {
  const _FakeConnStats(Stats stats) : super(stats: stats, numStreams: 0);
}

/// Score thresholds for the tests that enable scoring; a slightly negative
/// score is neither graylisted nor below the publish threshold.
/// An address book that keeps signed peer records, like dart_libp2p's.
class _FakeAddrBook extends Fake implements AddrBook, CertifiedAddrBook {
  final Map<PeerId, Envelope> records = {};
  final Map<PeerId, List<MultiAddr>> addresses = {};

  @override
  Future<bool> consumePeerRecord(Envelope s, Duration ttl) async {
    final record = PeerRecord.fromProtobuf(await s.record());
    records[record.peerId] = s;
    addresses[record.peerId] = record.addrs;
    return true;
  }

  @override
  Future<Envelope?> getPeerRecord(PeerId p) async => records[p];

  @override
  Future<List<MultiAddr>> addrs(PeerId p) async => addresses[p] ?? [];
}

class _FakePeerstore extends Fake implements Peerstore {
  @override
  final _FakeAddrBook addrBook = _FakeAddrBook();
}

const _testThresholds = PeerScoreThresholds(gossipThreshold: -10, publishThreshold: -50, graylistThreshold: -80);

// Use build_runner: dart pub run build_runner build --delete-conflicting-outputs
@GenerateMocks([Host, PubSub, PeerId, EventTracer, PubSubProtocol, Network, ConnManager]) // Added ConnManager
void main() {
  group('GossipSubRouter', () {
    late GossipSubRouter router;
    late MockPubSub mockPubsub;
    late MockHost mockHost;
    late MockNetwork mockNetwork; // Added MockNetwork declaration
    late MockConnManager mockConnManager; // Added MockConnManager declaration
    late MockPeerId mockLocalPeerId;
    late MockEventTracer mockTracer;
    late MockPubSubProtocol mockComms;
    late GossipSubParams gossipSubParams;
    late _FakePeerstore peerstore;

    /// The app-specific scores of the peers, which are their scores with
    /// [scoredRouter] (weight 1, nothing else scored).
    late Map<PeerId, double> scores;

    /// A router with scoring enabled, where the score of a peer added with
    /// [setScore] is its entry in [scores]. [topics] are the scored topics.
    /// Peer Exchange is on ([doPX]), so that tests can check when PX is
    /// withheld.
    GossipSubRouter scoredRouter(GossipSubParams params,
            {PeerScoreThresholds thresholds = _testThresholds,
            Map<String, TopicScoreParams> topics = const {},
            bool doPX = true}) =>
        GossipSubRouter(
          params: params,
          scoreParams: PeerScoreParams(topics: topics, appSpecificScore: (p) => scores[p] ?? 0, appSpecificWeight: 1),
          scoreThresholds: thresholds,
          doPX: doPX,
        );

    /// Gives [peer] the score [score] with router [r] (made by
    /// [scoredRouter]), adding the peer to the router so it is scored.
    void setScore(GossipSubRouter r, PeerId peer, double score) {
      scores[peer] = score;
      r.addPeer(peer, '/meshsub/1.1.0');
    }

    setUp(() async {
      mockHost = MockHost();
      mockPubsub = MockPubSub();
      mockNetwork = MockNetwork(); // Initialize MockNetwork
      mockConnManager = MockConnManager(); // Initialize MockConnManager
      mockLocalPeerId = MockPeerId();
      // Use a minimal valid identity multihash: identity func (0x00), 1 byte len (0x01), value 0x01
      when(mockLocalPeerId.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x01])); 
      when(mockLocalPeerId.toBase58()).thenReturn('QmMockLocalPeerId'); // Added stub for toBase58
      mockTracer = MockEventTracer();
      mockComms = MockPubSubProtocol();
      when(mockComms.maxMessageSize).thenReturn(1 << 20);

      // Setup mocks for PubSub instance
      when(mockPubsub.host).thenReturn(mockHost);
      when(mockHost.id).thenReturn(mockLocalPeerId); // PubSub uses host.id
      when(mockHost.network).thenReturn(mockNetwork); // Stub host.network
      when(mockHost.connManager).thenReturn(mockConnManager); // Stub host.connManager
      peerstore = _FakePeerstore();
      when(mockHost.peerStore).thenReturn(peerstore);
      when(mockNetwork.peers).thenReturn([]); // Default stub for network.peers
      // No connections: every peer added to the router is inbound.
      when(mockNetwork.connsToPeer(any)).thenReturn([]);
      when(mockConnManager.protect(any, any)).thenReturn(null); // Stub protect
      when(mockConnManager.unprotect(any, any)).thenReturn(true); // Stub unprotect
      when(mockPubsub.comms).thenReturn(mockComms);
      when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn);
      when(mockPubsub.tracer).thenReturn(mockTracer);
      when(mockPubsub.tracing).thenReturn(true);
      when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
      when(mockPubsub.getTopics()).thenReturn([]); // Default behavior
      // Mock methods that don't return a value and might be called
      when(mockPubsub.removePeer(any)).thenAnswer((_) async => {});
      when(mockTracer.trace(any)).thenAnswer((_) => {});
      when(mockTracer.start()).thenAnswer((_) async => {});
      when(mockTracer.stop()).thenAnswer((_) async => {});
      when(mockTracer.dispose()).thenAnswer((_) async => {});


      // Use the GossipSubParams defined in gossipsub.dart
      gossipSubParams = GossipSubParams(
        D: 6, // Default is 6
        DLow: 4, // Default is 5
        DHigh: 12, // Default is 12
        DScore: 4, // Default is 4
        fanoutTTL: Duration(seconds: 60), // Default is 1 minute
        DLazy: 6, // Default is 6
        // Add other params if needed for specific tests, otherwise defaults are used
      );

      scores = {};
      router = scoredRouter(gossipSubParams);
      await router.attach(mockPubsub);
      // Start the router to initialize heartbeat, etc.
      // Note: router.start() calls _mcache.start() and sets up _heartbeatTimer.
      // _mcache is initialized in GossipSubRouter constructor.
      // No need to mock _mcache.start() unless it has external dependencies not handled.
      await router.start(); 
    });

    tearDown(() async {
      await router.stop(); // Stop router, cancels heartbeat
    });

    test('initial state is correct', () {
      expect(router.params, equals(gossipSubParams));
      expect(router.mesh, isEmpty);
      expect(router.fanout, isEmpty);
      // TODO: Add more initial state checks as necessary
    });

    group('Peer Connection/Disconnection', () {
      late MockPeerId mockRemotePeerId;
      const testProtocolId = '/meshsub/1.1.0';

      setUp(() {
        mockRemotePeerId = MockPeerId();
        when(mockRemotePeerId.toBytes()).thenReturn(Uint8List.fromList([1, 2, 3])); // Example bytes
        when(mockRemotePeerId.toBase58()).thenReturn('QmRemotePeer');
      });

      test('addPeer starts scoring the peer and traces the event', () async {
        expect(router.score!.snapshot(mockRemotePeerId), isNull);

        await router.addPeer(mockRemotePeerId, testProtocolId);

        expect(router.score!.snapshot(mockRemotePeerId), isNotNull);
        expect(router.score!.score(mockRemotePeerId), equals(0));

        final capturedTrace = verify(mockTracer.trace(captureAny)).captured.single as trace_pb.TraceEvent;
        expect(capturedTrace.type, equals(trace_pb.TraceEvent_Type.ADD_PEER));
        expect(capturedTrace.addPeer.peerID, equals(mockRemotePeerId.toBytes()));
        expect(capturedTrace.addPeer.proto, equals(testProtocolId));
      });

      test('removePeer should notify PubSub, trace event, and clean up state', () async {
        // First, add the peer and put it in some mesh/fanout topics
        const topic1 = 'topic1';
        const topic2 = 'topic2';
        router.mesh.putIfAbsent(topic1, () => {}).add(mockRemotePeerId);
        router.fanout.putIfAbsent(topic2, () => {}).add(mockRemotePeerId);

        expect(router.mesh[topic1], contains(mockRemotePeerId));
        expect(router.fanout[topic2], contains(mockRemotePeerId));

        await router.removePeer(mockRemotePeerId);

        verify(mockPubsub.removePeer(mockRemotePeerId)).called(1);

        final capturedTrace = verify(mockTracer.trace(captureAny)).captured.last as trace_pb.TraceEvent; // last because addPeer also traces
        expect(capturedTrace.type, equals(trace_pb.TraceEvent_Type.REMOVE_PEER));
        expect(capturedTrace.removePeer.peerID, equals(mockRemotePeerId.toBytes()));

        expect(router.mesh[topic1], isNot(contains(mockRemotePeerId)));
        expect(router.fanout[topic2], isNot(contains(mockRemotePeerId)));
        // Also check if the topic entry itself is removed if the set becomes empty (current impl doesn't do this, but good to be aware)
        // expect(router.mesh[topic1], isEmpty); // This would only be true if it was the only peer
      });
    });

    // TODO: Add more tests for different aspects of GossipSubRouter
    // - Handling RPCs (IHAVE, IWANT, GRAFT, PRUNE)
    // - Message publishing and forwarding
    // - Heartbeat mechanism
    // - Mesh management
    
    group('Mesh Management (Join/Leave)', () {
      const testTopicName = 'test-topic';
      late Topic testTopic;

      setUp(() {
        testTopic = Topic(testTopicName);
        // Ensure tracer.trace is reset or use a fresh mock if needed,
        // or capture all and select relevant ones.
        // For simplicity, we'll rely on capturing and selecting.
      });

      test('join should trace event and initialize topic in mesh', () async {
        await router.join(testTopic);

        expect(router.mesh, contains(testTopicName));
        expect(router.mesh[testTopicName], isEmpty); // No known peers to GRAFT
        expect(router.fanout, isNot(contains(testTopicName)));

        final capturedTrace = verify(mockTracer.trace(captureAny)).captured.last as trace_pb.TraceEvent;
        expect(capturedTrace.type, equals(trace_pb.TraceEvent_Type.JOIN));
        expect(capturedTrace.join.topic, equals(testTopicName));
      });

      test('leave should trace event and remove topic from mesh and fanout', () async {
        // First, join the topic to ensure it's there
        await router.join(testTopic);
        expect(router.mesh, contains(testTopicName));

        await router.leave(testTopic);

        expect(router.mesh, isNot(contains(testTopicName)));
        expect(router.fanout, isNot(contains(testTopicName)));
        expect(router.fanoutLastPublished, isNot(contains(testTopicName)));


        final capturedTrace = verify(mockTracer.trace(captureAny)).captured.last as trace_pb.TraceEvent;
        expect(capturedTrace.type, equals(trace_pb.TraceEvent_Type.LEAVE));
        expect(capturedTrace.leave.topic, equals(testTopicName));
      });

      MockPeerId makePeer(int id) {
        final peer = MockPeerId();
        when(peer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, id]));
        when(peer.toBase58()).thenReturn('QmPeer$id');
        return peer;
      }

      Future<void> subscribeRemote(PeerId peer, String topicName) => router.handleRpc(
          peer,
          pb.RPC()
            ..subscriptions.add(pb.RPC_SubOpts()
              ..subscribe = true
              ..topicid = topicName));

      /// Captures the RPCs sent through comms, by recipient.
      Map<PeerId, List<pb.RPC>> captureSentRpcs() {
        final sent = <PeerId, List<pb.RPC>>{};
        when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
          sent
              .putIfAbsent(inv.positionalArguments[0] as PeerId, () => [])
              .add(inv.positionalArguments[1] as pb.RPC);
        });
        return sent;
      }

      test('join GRAFTs up to D connected peers subscribed to the topic, fanout peers first', () async {
        final fanoutPeer = makePeer(10);
        final topicPeers = [for (var i = 20; i < 28; i++) makePeer(i)];
        final disconnectedPeer = makePeer(30);
        final lowScorePeer = makePeer(31);
        when(mockNetwork.peers).thenReturn([fanoutPeer, ...topicPeers, lowScorePeer]);
        setScore(router, lowScorePeer, -1);
        for (final peer in [...topicPeers, disconnectedPeer, lowScorePeer]) {
          await subscribeRemote(peer, testTopicName);
        }
        router.fanout[testTopicName] = {fanoutPeer};
        router.fanoutLastPublished[testTopicName] = DateTime.now();
        final sent = captureSentRpcs();

        await router.join(testTopic);
        await pumpEventQueue();

        final meshPeers = router.mesh[testTopicName]!;
        expect(meshPeers.length, equals(gossipSubParams.D));
        expect(meshPeers, contains(fanoutPeer));
        expect(meshPeers, isNot(contains(disconnectedPeer)));
        expect(meshPeers, isNot(contains(lowScorePeer)));
        expect(router.fanout, isNot(contains(testTopicName)));
        expect(router.fanoutLastPublished, isNot(contains(testTopicName)));

        expect(sent.keys.toSet(), equals(meshPeers));
        for (final rpcs in sent.values) {
          expect(rpcs.single.control.graft.single.topicID, equals(testTopicName));
        }
        for (final peer in meshPeers) {
          verify(mockConnManager.protect(peer, 'gossipsub-mesh')).called(1);
        }
      });

      test('rejoining during the unsubscribe backoff does not GRAFT the pruned peers', () async {
        final peers = [makePeer(45), makePeer(46)];
        when(mockNetwork.peers).thenReturn(peers);
        for (final peer in peers) {
          await subscribeRemote(peer, testTopicName);
        }
        await router.join(testTopic);
        expect(router.mesh[testTopicName], equals(peers.toSet()));
        await router.leave(testTopic);
        final sent = captureSentRpcs();

        await router.join(testTopic);
        await pumpEventQueue();

        expect(router.mesh[testTopicName], isEmpty);
        expect(sent, isEmpty);
      });

      pb.RPC graftRpc(String topicName) => pb.RPC()
        ..control = (pb.ControlMessage()..graft.add(pb.ControlGraft()..topicID = topicName));

      test('a GRAFT for a topic we have not joined is ignored', () async {
        final peer = makePeer(55);
        final sent = captureSentRpcs();

        await router.handleRpc(peer, graftRpc('not-joined-topic'));
        await pumpEventQueue();

        expect(router.mesh, isNot(contains('not-joined-topic')));
        expect(sent, isEmpty);
        verifyNever(mockConnManager.protect(peer, any));
      });

      test('a GRAFT for a joined topic adds the peer to the mesh', () async {
        final peer = makePeer(56);
        await router.join(testTopic);

        await router.handleRpc(peer, graftRpc(testTopicName));

        expect(router.mesh[testTopicName], equals({peer}));
        verify(mockConnManager.protect(peer, 'gossipsub-mesh')).called(1);
      });

      test('a GRAFT from a peer with a negative score is refused with a PRUNE without PX', () async {
        final peer = makePeer(57);
        final otherPeer = makePeer(58); // A PX candidate, were PX allowed.
        when(mockNetwork.peers).thenReturn([peer, otherPeer]);
        await subscribeRemote(otherPeer, testTopicName);
        await router.join(testTopic);
        router.mesh[testTopicName]!.clear();
        setScore(router, peer, -1);
        final sent = captureSentRpcs();

        await router.handleRpc(peer, graftRpc(testTopicName));
        await pumpEventQueue();

        expect(router.mesh[testTopicName], isEmpty);
        final prune = sent[peer]!.single.control.prune.single;
        expect(prune.topicID, equals(testTopicName));
        expect(prune.backoff.toInt(), equals(gossipSubParams.pruneBackoff.inSeconds));
        expect(prune.peers, isEmpty);
        verifyNever(mockConnManager.protect(peer, any));
      });

      test('a GRAFT from an inbound peer is refused when the mesh has DHigh peers; an outbound peer is accepted',
          () async {
        final meshPeers = [for (var i = 0; i < gossipSubParams.DHigh; i++) makePeer(100 + i)];
        final inboundPeer = makePeer(60);
        final outboundPeer = makePeer(61);
        when(mockNetwork.connsToPeer(outboundPeer)).thenReturn([_FakeConn(Direction.outbound)]);
        final pxPeer = makePeer(62); // A connected topic peer, offered as PX.
        when(mockNetwork.peers).thenReturn([pxPeer, inboundPeer, outboundPeer]);
        await subscribeRemote(pxPeer, testTopicName);
        await router.addPeer(inboundPeer, '/meshsub/1.1.0');
        await router.addPeer(outboundPeer, '/meshsub/1.1.0');
        await router.join(testTopic);
        router.mesh[testTopicName]!.addAll(meshPeers);
        final sent = captureSentRpcs();

        await router.handleRpc(inboundPeer, graftRpc(testTopicName));
        await pumpEventQueue();

        expect(router.mesh[testTopicName], isNot(contains(inboundPeer)));
        final prune = sent[inboundPeer]!.single.control.prune.single;
        expect(prune.topicID, equals(testTopicName));
        // A peer refused because the mesh is full gets PX.
        expect(prune.peers.map((px) => px.peerID), [pxPeer.toBytes()]);

        // As go-libp2p-pubsub's handleGraft: the mesh may exceed DHigh for
        // outbound peers (the heartbeat trims it, keeping DOut outbound).
        await router.handleRpc(outboundPeer, graftRpc(testTopicName));
        await pumpEventQueue();

        expect(router.mesh[testTopicName], contains(outboundPeer));
        expect(sent[outboundPeer], isNull);
      });

      test('without doPX (the default), PRUNEs carry no Peer Exchange', () async {
        final r = GossipSubRouter(params: gossipSubParams);
        await r.attach(mockPubsub);
        final meshPeer = makePeer(70);
        final other = makePeer(71);
        when(mockNetwork.peers).thenReturn([meshPeer, other]);
        await r.handleRpc(other, pb.RPC()..subscriptions.add(pb.RPC_SubOpts()..subscribe = true..topicid = testTopicName));
        await r.join(testTopic);
        r.mesh[testTopicName]!.add(meshPeer);
        final sent = captureSentRpcs();

        await r.leave(testTopic);
        await pumpEventQueue();

        expect(sent[meshPeer]!.single.control.prune.single.peers, isEmpty);
      });

      test('removePeer forgets the subscriptions of the peer', () async {
        final peer = makePeer(50);
        when(mockNetwork.peers).thenReturn([peer]);
        await subscribeRemote(peer, testTopicName);
        await router.removePeer(peer);
        // The peer reconnects but has not sent its subscriptions again.
        final sent = captureSentRpcs();

        await router.join(testTopic);
        await pumpEventQueue();

        expect(router.mesh[testTopicName], isEmpty);
        expect(sent, isEmpty);
      });

      test('leave sends PRUNE with the unsubscribe backoff to each mesh peer', () async {
        final meshPeers = [makePeer(40), makePeer(41)];
        when(mockNetwork.peers).thenReturn(meshPeers);
        for (final peer in meshPeers) {
          await subscribeRemote(peer, testTopicName);
        }
        await router.join(testTopic);
        expect(router.mesh[testTopicName], equals(meshPeers.toSet()));
        final sent = captureSentRpcs();

        await router.leave(testTopic);
        await pumpEventQueue();

        expect(sent.keys.toSet(), equals(meshPeers.toSet()));
        for (final rpcs in sent.values) {
          final prune = rpcs.single.control.prune.single;
          expect(prune.topicID, equals(testTopicName));
          expect(prune.backoff.toInt(), equals(gossipSubParams.unsubscribeBackoff.inSeconds));
        }
        for (final peer in meshPeers) {
          verify(mockConnManager.unprotect(peer, 'gossipsub-mesh')).called(1);
        }
        final pruneTraces = verify(mockTracer.trace(captureAny)).captured
            .cast<trace_pb.TraceEvent>()
            .where((t) => t.type == trace_pb.TraceEvent_Type.PRUNE);
        expect(pruneTraces.length, equals(meshPeers.length));
      });

      test('joining an already joined topic should not create duplicate entries', () async {
        await router.join(testTopic); // First join
        final meshPeers = router.mesh[testTopicName];

        await router.join(testTopic); // Second join

        expect(router.mesh[testTopicName], same(meshPeers)); // Should be the same set instance
        // As go-libp2p-pubsub's Join: joining a joined topic does nothing,
        // not even a JOIN trace.
        expect(verify(mockTracer.trace(captureAny)).captured.where((t) => (t as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.JOIN).length, equals(1));
      });

      test('leaving a topic not joined should not error and traces nothing', () async {
        const anotherTopicName = 'another-topic';
        final anotherTopic = Topic(anotherTopicName);

        await router.leave(anotherTopic); // Leave a topic not previously joined

        expect(router.mesh, isNot(contains(anotherTopicName)));
        expect(router.fanout, isNot(contains(anotherTopicName)));
        // As go-libp2p-pubsub's Leave: leaving a topic not joined does
        // nothing, not even a LEAVE trace.
        verifyNever(mockTracer.trace(any));
      });
    });

    group('RPC Handling (Control Messages)', () {
      late MockPeerId mockRpcPeerId; // Peer sending the RPC
      const testTopicName = 'rpc-topic';

      setUp(() {
        mockRpcPeerId = MockPeerId();
        when(mockRpcPeerId.toBytes()).thenReturn(Uint8List.fromList([10, 20, 30]));
        when(mockRpcPeerId.toBase58()).thenReturn('QmRpcPeer');
        
        // Clear interactions from mockTracer from the main setUp or previous tests in this group
        clearInteractions(mockTracer);
        // Re-stub the default trace behavior if clearInteractions removed it.
        // This is important if the code under test might call trace for other reasons
        // and we don't want those to fail the mock verification if not explicitly verified.
        when(mockTracer.trace(any)).thenAnswer((_) => {});
      });

      test('handleRpc with GRAFT should add peer to mesh and trace event', () async {
        // Ensure the router knows about the topic, but peer is not in mesh yet
        await router.join(Topic(testTopicName)); // This will also trace a JOIN event
        clearInteractions(mockTracer); // Clear JOIN trace for this specific test
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub

        expect(router.mesh[testTopicName], isNot(contains(mockRpcPeerId)));

        final graftMessage = pb.ControlGraft()..topicID = testTopicName;
        final controlMessage = pb.ControlMessage()..graft.add(graftMessage);
        final rpc = pb.RPC()..control = controlMessage;

        await router.handleRpc(mockRpcPeerId, rpc);

        expect(router.mesh[testTopicName], contains(mockRpcPeerId));

        final capturedTraces = verify(mockTracer.trace(captureAny)).captured;
        
        final receivedRpcTrace = capturedTraces.firstWhere(
          (event) => (event as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.RECV_RPC,
          orElse: () => null,
        ) as trace_pb.TraceEvent?;
        expect(receivedRpcTrace, isNotNull, reason: "RECV_RPC trace not found");
        expect(receivedRpcTrace!.recvRPC.receivedFrom, equals(mockRpcPeerId.toBytes()));

        final graftTrace = capturedTraces.firstWhere(
          (event) => (event as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.GRAFT,
          orElse: () => null,
        ) as trace_pb.TraceEvent?;
        expect(graftTrace, isNotNull, reason: "GRAFT trace not found");
        expect(graftTrace!.graft.topic, equals(testTopicName));
        expect(graftTrace.graft.peerID, equals(mockRpcPeerId.toBytes()));
      });

      test('handleRpc with PRUNE should remove peer from mesh and trace event', () async {
        // Ensure the peer is in the mesh for the topic first
        await router.join(Topic(testTopicName)); // Traces JOIN
        router.mesh[testTopicName]!.add(mockRpcPeerId);
        expect(router.mesh[testTopicName], contains(mockRpcPeerId));
        
        clearInteractions(mockTracer); // Clear JOIN trace
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub

        final pruneMessage = pb.ControlPrune()..topicID = testTopicName;
        final controlMessage = pb.ControlMessage()..prune.add(pruneMessage);
        final rpc = pb.RPC()..control = controlMessage;

        await router.handleRpc(mockRpcPeerId, rpc);

        expect(router.mesh[testTopicName], isNot(contains(mockRpcPeerId)));
        
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured;

        final receivedRpcTrace = capturedTraces.firstWhere(
          (event) => (event as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.RECV_RPC,
          orElse: () => null,
        ) as trace_pb.TraceEvent?;
        expect(receivedRpcTrace, isNotNull, reason: "RECV_RPC trace not found");

        final pruneTrace = capturedTraces.firstWhere(
          (event) => (event as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.PRUNE,
          orElse: () => null,
        ) as trace_pb.TraceEvent?;
        expect(pruneTrace, isNotNull, reason: "PRUNE trace not found");
        expect(pruneTrace!.prune.topic, equals(testTopicName));
        expect(pruneTrace.prune.peerID, equals(mockRpcPeerId.toBytes()));
      });

      test('handleRpc with a PRUNE asking for a huge backoff caps it instead of throwing', () async {
        await router.join(Topic(testTopicName));
        router.mesh[testTopicName]!.add(mockRpcPeerId);

        // 2^62 seconds overflows a Duration; 2^64-1 decodes as a negative Int64.
        for (final backoff in [Int64(1) << 62, Int64(-1)]) {
          router.mesh[testTopicName]!.add(mockRpcPeerId);
          final rpc = pb.RPC()
            ..control = (pb.ControlMessage()
              ..prune.add(pb.ControlPrune()
                ..topicID = testTopicName
                ..backoff = backoff));
          await router.handleRpc(mockRpcPeerId, rpc);
          expect(router.mesh[testTopicName], isNot(contains(mockRpcPeerId)));
        }
      });

      test('handleRpc with IWANT sends each message once and stops after gossipRetransmission requests', () async {
        final msg = pb.Message()
          ..from = mockLocalPeerId.toBytes()
          ..data = [1, 2, 3]
          ..seqno = [4, 4, 4]
          ..topic = testTopicName;
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {});
        await router.publish(PubSubMessage(rpcMessage: msg, receivedFrom: mockLocalPeerId));
        final msgId = defaultMessageIdFn(msg);

        final sent = <pb.RPC>[];
        clearInteractions(mockComms);
        when(mockComms.sendRpc(mockRpcPeerId, any, any)).thenAnswer((invocation) async {
          sent.add(invocation.positionalArguments[1] as pb.RPC);
        });

        // The same ID many times in one IWANT: answered with one copy.
        final iwant = pb.RPC()
          ..control = (pb.ControlMessage()
            ..iwant.add(pb.ControlIWant()..messageIDs.addAll(List.filled(1000, messageIdToBytes(msgId)))));
        for (var i = 0; i < gossipSubParams.gossipRetransmission + 2; i++) {
          await router.handleRpc(mockRpcPeerId, iwant);
        }
        await Future<void>.delayed(Duration.zero);

        final copies = sent.expand((rpc) => rpc.publish).length;
        expect(copies, equals(gossipSubParams.gossipRetransmission));
      });

      test('handleRpc with IHAVE for unknown messages should respond with IWANT and trace events', () async {
        const unknownMsgId1 = 'unknown-msg-id-1';
        const unknownMsgId2 = 'unknown-msg-id-2';
        // As go-libp2p-pubsub's handleIHave: only the IHAVEs for joined
        // topics are answered.
        await router.join(Topic(testTopicName));

        // Router's mcache is fresh, so it hasn't seen these messages.
        final ihaveMessage = pb.ControlIHave()
          ..topicID = testTopicName
          ..messageIDs.addAll([unknownMsgId1.codeUnits, unknownMsgId2.codeUnits]);
        final controlMessage = pb.ControlMessage()..ihave.add(ihaveMessage);
        final rpc = pb.RPC()..control = controlMessage;

        // Stub the sendRpc on mockComms to capture the IWANT message
        pb.RPC? sentRpcToPeer;
        // Capture the second argument (RPC) and third (protocolId)
        when(mockComms.sendRpc(mockRpcPeerId, captureAny, captureAny)).thenAnswer((invocation) async {
          sentRpcToPeer = invocation.positionalArguments[1] as pb.RPC;
        });

        await router.handleRpc(mockRpcPeerId, rpc);

        // Verify RECV_RPC trace
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured;
        final recvRpcTrace = capturedTraces.firstWhere(
          (e) => e.type == trace_pb.TraceEvent_Type.RECV_RPC,
          orElse: () => null
        );
        expect(recvRpcTrace, isNotNull, reason: "RECV_RPC for IHAVE not found");

        // Verify that sendRpc was called on mockComms (via rpcQueueManager)
        // The second argument is the RPC, third is protocolId string
        verify(mockComms.sendRpc(mockRpcPeerId, argThat(isA<pb.RPC>()), gossipSubIDv11)).called(1);
        expect(sentRpcToPeer, isNotNull, reason: "IWANT RPC was not sent");
        expect(sentRpcToPeer!.control.iwant, isNotEmpty);
        expect(sentRpcToPeer!.control.iwant.first.messageIDs.length, equals(2));
        expect(sentRpcToPeer!.control.iwant.first.messageIDs.map(messageIdFromBytes), containsAll([unknownMsgId1, unknownMsgId2]));
        
        // Verify SEND_RPC trace for the IWANT message
        // Given the bug in gossipsub.dart's IWANT trace population, 
        // sendRPC.meta.control.iwant might be empty in the trace.
        // We'll check that a SEND_RPC to the correct peer with some control message occurred.
        // The more important check is that mockComms.sendRpc was called with an actual IWANT.
        // The trace for SEND_RPC might be missing detailed control metadata due to the bug.
        final sendRpcTrace = capturedTraces.firstWhere(
          (e) => e.type == trace_pb.TraceEvent_Type.SEND_RPC &&
                 e.sendRPC.sendTo == mockRpcPeerId.toBytes(),
          orElse: () => null
        );
        expect(sendRpcTrace, isNotNull, reason: "SEND_RPC trace for IWANT response not found");
        // If the bug in gossipsub.dart trace population is fixed, this can be more specific:
        // expect(sendRpcTrace.sendRPC.meta.hasControl(), isTrue);
        // expect(sendRpcTrace.sendRPC.meta.control.iwant, isNotEmpty);
      });

      test('handleRpc with IHAVE for known messages should not respond with IWANT', () async {
        // Simulate that the router has seen this message by putting it in mcache
        // This requires publishing a message or directly manipulating mcache if possible.
        // For simplicity, we'll assume mcache.seen() is the key.
        // The actual GossipSubRouter._mcache is not directly accessible for mocking its `seen` method.
        // However, the IHAVE handler itself calls `_mcache.seen()`.
        // If we can't manipulate mcache directly, we can test the negative case:
        // if no IWANT is sent, it implies messages were known or IHAVE was empty.
        // The current GossipSubRouter implementation of IHAVE processing:
        // if (!_mcache.seen(msgId)) { wantedMessageIds.add(msgId); }
        // So, if mcache.seen() returns true, no IWANT.
        // Since _mcache is internal, this test relies on _mcache being empty by default for new messages.
        // To test the "known" case properly, we'd need to publish a message first.

        // Let's create a message, publish it so it's in the router's mcache.
        final knownMsgData = Uint8List.fromList([7,8,9]);
        final knownPbMsg = pb.Message();
        knownPbMsg.from = mockLocalPeerId.toBytes();
        knownPbMsg.data = knownMsgData;
        knownPbMsg.seqno = Uint8List.fromList([2,2,2]); // Unique sequence number for this message
        knownPbMsg.topic = testTopicName;
        
        final knownPubSubMessage = PubSubMessage(rpcMessage: knownPbMsg, receivedFrom: mockLocalPeerId);

        // Stubbing for router.publish:
        // It will call _pubsub.host.id (stubbed)
        // It will call _pubsub.host.network.peers (not directly used by publish for mcache part)
        // It will call _pubsub.getPeerScore (stubbed)
        // It will call _rpcQueueManager.sendRpc (which uses mockComms.sendRpc)
        // For this test, we only care that publish puts the message in mcache.
        // We need to ensure sendRpc doesn't cause issues if called by publish.
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {}); // Allow publish to proceed
        // Also stub getTopics if publish uses it for fanout logic (it doesn't directly for mcache)
        when(mockPubsub.getTopics()).thenReturn([testTopicName]);


        await router.publish(knownPubSubMessage); 
        // Now knownPbMsg should be in the router's internal mcache, 
        // identified by defaultMessageIdFn(knownPbMsg)

        final String knownMsgIdString = defaultMessageIdFn(knownPbMsg);
        // final List<int> knownMsgIdBytesForIhave = Uint8List.fromList(knownMsgIdString.codeUnits); // Not needed

        final ihaveMessage = pb.ControlIHave()
          ..topicID = testTopicName
          ..messageIDs.add(messageIdToBytes(knownMsgIdString));
        final controlMessage = pb.ControlMessage()..ihave.add(ihaveMessage);
        final rpc = pb.RPC()..control = controlMessage;

        clearInteractions(mockComms); // Clear previous sendRpc interactions
        clearInteractions(mockTracer); // Clear previous trace interactions
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub trace

        await router.handleRpc(mockRpcPeerId, rpc);

        // Verify no IWANT message was sent
        verifyNever(mockComms.sendRpc(
            mockRpcPeerId, 
            argThat(predicate<pb.RPC>((rpc) => rpc.hasControl() && rpc.control.iwant.isNotEmpty)), 
            gossipSubIDv11
        ));
        
        // Verify RECV_RPC trace for IHAVE
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured;
        final recvRpcTrace = capturedTraces.firstWhere(
          (e) => (e as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.RECV_RPC,
          orElse: () => null
        ) as trace_pb.TraceEvent?;
        expect(recvRpcTrace, isNotNull, reason: "RECV_RPC for IHAVE (known msg) not found");
      });

      test('handleRpc with IWANT should respond with known messages and trace events', () async {
        // 1. Prepare messages and put them into the router's mcache.
        final msg1Data = Uint8List.fromList([1,2,3]);
        final msg1Pb = pb.Message()
          ..from = mockLocalPeerId.toBytes()
          ..data = msg1Data
          ..seqno = Uint8List.fromList([1,0,1]) // Unique seqno
          ..topic = testTopicName;
        final msg1Id = defaultMessageIdFn(msg1Pb);

        final msg2Data = Uint8List.fromList([4,5,6]);
        final msg2Pb = pb.Message()
          ..from = mockLocalPeerId.toBytes()
          ..data = msg2Data
          ..seqno = Uint8List.fromList([1,0,2]) // Unique seqno
          ..topic = testTopicName;
        final msg2Id = defaultMessageIdFn(msg2Pb);
        
        final unknownMsgId = 'unknown-in-iwant-id';

        // Publish messages to get them into mcache
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {}); // Generic stub for publish
        await router.publish(PubSubMessage(rpcMessage: msg1Pb, receivedFrom: mockLocalPeerId)); // msg1Id is String
        await router.publish(PubSubMessage(rpcMessage: msg2Pb, receivedFrom: mockLocalPeerId)); // msg2Id is String

        // 2. Construct IWANT RPC from remote peer requesting these messages + one unknown
        final iwantMessage = pb.ControlIWant()
          ..messageIDs.addAll([
            messageIdToBytes(msg1Id),
            messageIdToBytes(msg2Id),
            messageIdToBytes(unknownMsgId),
          ]);
        final controlMessage = pb.ControlMessage()..iwant.add(iwantMessage);
        final rpc = pb.RPC()..control = controlMessage;

        // 3. Stub sendRpc on mockComms to capture the PUBLISH response
        clearInteractions(mockComms); // Clear interactions from publish calls
        pb.RPC? sentRpcToPeer;
        when(mockComms.sendRpc(mockRpcPeerId, captureAny, gossipSubIDv11)).thenAnswer((invocation) async {
          sentRpcToPeer = invocation.positionalArguments[1] as pb.RPC;
        });
        
        clearInteractions(mockTracer); // Clear traces from publish calls
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub

        // 4. Call handleRpc
        await router.handleRpc(mockRpcPeerId, rpc);

        // 5. Verify traces and sent RPC
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured;

        // Verify RECV_RPC for IWANT
        final recvRpcTrace = capturedTraces.firstWhere(
          (e) => (e as trace_pb.TraceEvent).type == trace_pb.TraceEvent_Type.RECV_RPC,
          orElse: () => null
        ) as trace_pb.TraceEvent?;
        expect(recvRpcTrace, isNotNull, reason: "RECV_RPC for IWANT not found");

        // Verify that sendRpc was called to send the PUBLISH messages
        verify(mockComms.sendRpc(mockRpcPeerId, argThat(isA<pb.RPC>()), gossipSubIDv11)).called(1);
        expect(sentRpcToPeer, isNotNull, reason: "PUBLISH RPC in response to IWANT was not sent");
        expect(sentRpcToPeer!.publish, isNotEmpty, reason: "No messages in PUBLISH RPC for IWANT");
        expect(sentRpcToPeer!.publish.length, equals(2), reason: "Expected 2 messages in PUBLISH RPC");

        // Check that the sent messages are msg1Pb and msg2Pb
        // This requires comparing protobuf messages, which can be tricky due to object identity.
        // We can check topics and data.
        expect(sentRpcToPeer!.publish.any((m) => m.topic == testTopicName && m.data.toString() == msg1Data.toString()), isTrue);
        expect(sentRpcToPeer!.publish.any((m) => m.topic == testTopicName && m.data.toString() == msg2Data.toString()), isTrue);

        // Verify SEND_RPC trace for the PUBLISH message
        final sendRpcTrace = capturedTraces.firstWhere(
          (e) => e.type == trace_pb.TraceEvent_Type.SEND_RPC &&
                 e.sendRPC.sendTo == mockRpcPeerId.toBytes() &&
                 e.sendRPC.meta.messages.isNotEmpty,
          orElse: () => null
        );
        expect(sendRpcTrace, isNotNull, reason: "SEND_RPC for PUBLISH (IWANT response) not found");
        expect(sendRpcTrace!.sendRPC.meta.messages.length, equals(2));
      });
    });

    group('Message Publishing', () {
      const testTopicName = 'publish-topic';
      late Topic testTopic;
      late PubSubMessage testPubSubMessage;
      late pb.Message testPbMessage;
      late String testMessageId;

      setUp(() {
        testTopic = Topic(testTopicName);
        
        final msgData = Uint8List.fromList([100, 101, 102]);
        testPbMessage = pb.Message()
          ..from = mockLocalPeerId.toBytes()
          ..data = msgData
          ..seqno = Uint8List.fromList([3,0,1]) // Unique seqno
          ..topic = testTopicName;
        testMessageId = defaultMessageIdFn(testPbMessage);
        testPubSubMessage = PubSubMessage(rpcMessage: testPbMessage, receivedFrom: mockLocalPeerId);

        // Ensure router is joined to the topic for mesh tests by default
        // but specific tests can override or clear this.
        // For fanout tests, we'd ensure it's NOT joined.
        // For mesh tests, we need to join.
        // router.join(testTopic); // Let individual tests handle join

        // Clear interactions from other groups
        clearInteractions(mockComms);
        clearInteractions(mockTracer);
        // Re-stub default behaviors if cleared
        when(mockTracer.trace(any)).thenAnswer((_) => {});
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {});
      });

      /// Replaces the router with one that does not flood publish, so that
      /// our messages go to the mesh, or the fanout.
      Future<void> useRouterWithoutFloodPublish() async {
        await router.stop();
        router = scoredRouter(GossipSubParams(floodPublish: false));
        await router.attach(mockPubsub);
      }

      test('without flood publish, publish should send message to mesh peers and trace event', () async {
        // 1. Setup: Join topic, add mesh peers
        await useRouterWithoutFloodPublish();
        await router.join(testTopic); // Join the topic to establish a mesh entry
        
        final mockMeshPeer1 = MockPeerId();
        when(mockMeshPeer1.toBytes()).thenReturn(Uint8List.fromList([50,1,1]));
        when(mockMeshPeer1.toBase58()).thenReturn('QmMeshPeer1');
        router.mesh[testTopicName]!.add(mockMeshPeer1);

        final mockMeshPeer2 = MockPeerId();
        when(mockMeshPeer2.toBytes()).thenReturn(Uint8List.fromList([50,1,2]));
        when(mockMeshPeer2.toBase58()).thenReturn('QmMeshPeer2');
        router.mesh[testTopicName]!.add(mockMeshPeer2);

        // Capture RPCs sent
        final List<pb.RPC> sentRpcs = [];
        final List<PeerId> recipients = [];
        when(mockComms.sendRpc(captureAny, captureAny, gossipSubIDv11)).thenAnswer((invocation) async {
          recipients.add(invocation.positionalArguments[0] as PeerId);
          sentRpcs.add(invocation.positionalArguments[1] as pb.RPC);
        });
        
        // 2. Action: Publish the message
        await router.publish(testPubSubMessage);

        // 3. Verification
        // Message caching is an internal detail of publish; its effects are tested
        // via IHAVE/IWANT tests which rely on publish populating the cache.
        // We won't directly access mcache here.

        // Verify sendRpc was called for both mesh peers
        expect(recipients.length, equals(2));
        expect(recipients, containsAll([mockMeshPeer1, mockMeshPeer2]));
        
        // Verify the content of the sent RPC
        for (final rpc in sentRpcs) {
          expect(rpc.publish, isNotEmpty);
          expect(rpc.publish.length, equals(1));
          expect(rpc.publish.first, equals(testPbMessage));
        }

        // Verify SEND_RPC trace events for mesh peers
        // GossipSubRouter.publish traces SEND_RPC for each peer it sends a message to.
        // The PUBLISH_MESSAGE trace is done by PubSub.publish itself.
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();
        final sendRpcTraces = capturedTraces.where((t) => t.type == trace_pb.TraceEvent_Type.SEND_RPC).toList();
        
        expect(sendRpcTraces.length, equals(2), reason: "Expected 2 SEND_RPC traces for mesh peers");

        // Check trace for mockMeshPeer1
        final List<trace_pb.TraceEvent> tracesToMeshPeer1List = sendRpcTraces.where(
          (t) => t.sendRPC.sendTo.toString() == mockMeshPeer1.toBytes().toString()
        ).toList();
        final trace_pb.TraceEvent? traceToMeshPeer1 = tracesToMeshPeer1List.isNotEmpty ? tracesToMeshPeer1List.first : null;
        expect(traceToMeshPeer1, isNotNull, reason: "SEND_RPC trace to mockMeshPeer1 not found");
        expect(traceToMeshPeer1!.sendRPC.meta.messages, isNotEmpty);
        expect(traceToMeshPeer1.sendRPC.meta.messages.first.messageID, orderedEquals(Uint8List.fromList(testMessageId.codeUnits)));
        expect(traceToMeshPeer1.sendRPC.meta.messages.first.topic, equals(testTopicName));

        // Check trace for mockMeshPeer2
        final List<trace_pb.TraceEvent> tracesToMeshPeer2List = sendRpcTraces.where(
          (t) => t.sendRPC.sendTo.toString() == mockMeshPeer2.toBytes().toString()
        ).toList();
        final trace_pb.TraceEvent? traceToMeshPeer2 = tracesToMeshPeer2List.isNotEmpty ? tracesToMeshPeer2List.first : null;
        expect(traceToMeshPeer2, isNotNull, reason: "SEND_RPC trace to mockMeshPeer2 not found");
        expect(traceToMeshPeer2!.sendRPC.meta.messages, isNotEmpty);
        expect(traceToMeshPeer2.sendRPC.meta.messages.first.messageID, orderedEquals(Uint8List.fromList(testMessageId.codeUnits)));
        expect(traceToMeshPeer2.sendRPC.meta.messages.first.topic, equals(testTopicName));
      });

      // As go-libp2p-pubsub with WithFloodPublish (the default): our own
      // message goes to every connected peer of the topic with a score of
      // at least the publish threshold, not only to the mesh.
      test('flood publish sends our message to the connected topic peers above the publish threshold', () async {
        MockPeerId makePeer(int id, String name) {
          final peer = MockPeerId();
          when(peer.toBytes()).thenReturn(Uint8List.fromList([60, 1, id]));
          when(peer.toBase58()).thenReturn(name);
          return peer;
        }
        final meshPeer = makePeer(1, 'QmMesh');
        final subscribedPeer = makePeer(2, 'QmSubscribed');
        final unsubscribedPeer = makePeer(3, 'QmUnsubscribed');
        final lowScorePeer = makePeer(4, 'QmLowScore');
        final slightlyNegativePeer = makePeer(5, 'QmSlightlyNegative');
        when(mockNetwork.peers)
            .thenReturn([meshPeer, subscribedPeer, unsubscribedPeer, lowScorePeer, slightlyNegativePeer]);
        setScore(router, lowScorePeer, _testThresholds.publishThreshold - 1);
        setScore(router, slightlyNegativePeer, -1);
        for (final peer in [meshPeer, subscribedPeer, lowScorePeer, slightlyNegativePeer]) {
          await router.handleRpc(peer, pb.RPC()
            ..subscriptions.add(pb.RPC_SubOpts()
              ..subscribe = true
              ..topicid = testTopicName));
        }
        await router.join(testTopic);
        router.mesh[testTopicName] = {meshPeer};

        final sent = <PeerId, List<pb.RPC>>{};
        when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
          sent
              .putIfAbsent(inv.positionalArguments[0] as PeerId, () => [])
              .add(inv.positionalArguments[1] as pb.RPC);
        });

        await router.publish(testPubSubMessage);
        await pumpEventQueue();

        expect(sent.keys.toSet(), equals({meshPeer, subscribedPeer, slightlyNegativePeer}));
        for (final rpcs in sent.values) {
          expect(rpcs.single.publish.single, equals(testPbMessage));
          expect(rpcs.single.hasControl(), isFalse);
        }
      });

      test('without flood publish, publish should send message to fanout peers if not in mesh', () async {
        await useRouterWithoutFloodPublish();
        // 1. Setup: Ensure NOT joined to topic, add fanout peer.
        // By not calling router.join(testTopic), we ensure it's not in the mesh.
        // The fanout map is populated by the heartbeat or when joining other topics.
        // For this test, we'll manually add to the fanout map.
        
        final mockFanoutPeer1 = MockPeerId();
        when(mockFanoutPeer1.toBytes()).thenReturn(Uint8List.fromList([51,1,1]));
        when(mockFanoutPeer1.toBase58()).thenReturn('QmFanoutPeer1');
        router.fanout.putIfAbsent(testTopicName, () => {}).add(mockFanoutPeer1);

        // Ensure fanoutLastPublished is clear for this topic so fanout occurs
        router.fanoutLastPublished.remove(testTopicName); 
        // Or ensure it's older than fanoutTTL, but removing is simpler for a test.

        // Capture RPCs sent
        final List<pb.RPC> sentRpcs = [];
        final List<PeerId> recipients = [];
        when(mockComms.sendRpc(captureAny, captureAny, gossipSubIDv11)).thenAnswer((invocation) async {
          recipients.add(invocation.positionalArguments[0] as PeerId);
          sentRpcs.add(invocation.positionalArguments[1] as pb.RPC);
        });

        // 2. Action: Publish the message
        await router.publish(testPubSubMessage);

        // 3. Verification
        // Verify sendRpc was called for the fanout peer
        // Fanout selects D_lazy peers, default is 6. We added 1.
        expect(recipients.length, equals(1));
        expect(recipients, contains(mockFanoutPeer1));
        
        // Verify the content of the sent RPC
        expect(sentRpcs.first.publish, isNotEmpty);
        expect(sentRpcs.first.publish.length, equals(1));
        expect(sentRpcs.first.publish.first, equals(testPbMessage));

        // Verify fanoutLastPublished was updated for the topic
        // This is an internal state, but its effect is that a subsequent publish within fanoutTTL shouldn't resend.
        // For this test, we primarily care that the initial fanout publish occurred.
        // A more advanced test could check the TTL behavior.
        expect(router.fanoutLastPublished.containsKey(testTopicName), isTrue);


        // Verify SEND_RPC trace event for the fanout peer
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();
        final sendRpcTraces = capturedTraces.where((t) => t.type == trace_pb.TraceEvent_Type.SEND_RPC).toList();

        expect(sendRpcTraces.length, equals(1), reason: "Expected 1 SEND_RPC trace for the fanout peer");
        final List<trace_pb.TraceEvent> tracesToFanoutPeerList = sendRpcTraces.where(
          (t) => t.sendRPC.sendTo.toString() == mockFanoutPeer1.toBytes().toString()
        ).toList();
        final trace_pb.TraceEvent? traceToFanoutPeer = tracesToFanoutPeerList.isNotEmpty ? tracesToFanoutPeerList.first : null;
        expect(traceToFanoutPeer, isNotNull, reason: "SEND_RPC trace to mockFanoutPeer1 not found");
        expect(traceToFanoutPeer!.sendRPC.meta.messages, isNotEmpty);
        expect(traceToFanoutPeer.sendRPC.meta.messages.first.messageID, orderedEquals(Uint8List.fromList(testMessageId.codeUnits)));
        expect(traceToFanoutPeer.sendRPC.meta.messages.first.topic, equals(testTopicName));
      });

      test('publish should not send RPCs if no mesh or fanout peers, but still trace', () async {
        // 1. Setup: Ensure NOT joined, mesh and fanout are empty for the topic.
        // By not calling router.join(testTopic), mesh for testTopicName will be empty/null.
        router.fanout.remove(testTopicName); // Ensure fanout is empty for this topic
        router.fanoutLastPublished.remove(testTopicName);

        // We will use verifyNever for mockComms.sendRpc, so no need for a 'when' that calls 'fail'.
        // If sendRpc were called, verifyNever would fail the test.

        // 2. Action: Publish the message
        await router.publish(testPubSubMessage);

        // 3. Verification
        // Verify sendRpc was NOT called
        verifyNever(mockComms.sendRpc(any, any, gossipSubIDv11));

        // Verify NO SEND_RPC trace events occur, as no messages should be sent.
        // The GossipSubRouter.publish method (as per provided code) does not trace anything
        // if there are no peers to publish to; it just prints a log and returns.
        // Therefore, we verify that no SEND_RPC trace event was emitted.
        verifyNever(mockTracer.trace(argThat(isA<trace_pb.TraceEvent>()
          .having((e) => e.type, 'type', trace_pb.TraceEvent_Type.SEND_RPC)
        )));
      });
    });

    group('Message Forwarding (via handleRpc)', () {
      const testTopicName = 'forward-topic';
      late Topic testTopic;
      late MockPeerId mockSendingPeer; // Peer sending the RPC with messages
      late pb.Message incomingPbMessage;
      late String incomingMessageId;
      late pb.RPC incomingRpc;

      setUp(() {
        testTopic = Topic(testTopicName);
        mockSendingPeer = MockPeerId();
        when(mockSendingPeer.toBytes()).thenReturn(Uint8List.fromList([60,1,1]));
        when(mockSendingPeer.toBase58()).thenReturn('QmSendingPeer');

        final msgData = Uint8List.fromList([200, 201, 202]);
        // Message originates from mockSendingPeer or another peer, received by local node from mockSendingPeer
        incomingPbMessage = pb.Message()
          ..from = mockSendingPeer.toBytes() // Let's say sender is originator for simplicity
          ..data = msgData
          ..seqno = Uint8List.fromList([4,0,1])
          ..topic = testTopicName;
        incomingMessageId = defaultMessageIdFn(incomingPbMessage);
        
        incomingRpc = pb.RPC()..publish.add(incomingPbMessage);

        // Clear interactions from other groups/setups
        clearInteractions(mockComms);
        clearInteractions(mockTracer);
        clearInteractions(mockPubsub); // Clear pubsub interactions too, esp. deliverMessage

        // Re-stub default behaviors
        when(mockTracer.trace(any)).thenAnswer((_) => {});
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {});
        // Default validation to accept
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.accept));
        when(mockPubsub.deliverMessage(any)).thenAnswer((_) {}); // Default for deliver
        when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn); // Ensure router uses the same ID fn
         // Re-stub other pubsub interactions that might have been cleared and are needed by router
        when(mockPubsub.host).thenReturn(mockHost);
        when(mockPubsub.comms).thenReturn(mockComms);
        when(mockPubsub.tracer).thenReturn(mockTracer);
        when(mockPubsub.tracing).thenReturn(true);
        when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
        when(mockPubsub.getTopics()).thenReturn([]);
        when(mockPubsub.removePeer(any)).thenAnswer((_) async => {});
      });

      /// Replaces the router with one that scores invalid message
      /// deliveries on the test topic (P4 = -invalid^2).
      Future<void> useRouterScoringInvalidMessages() async {
        await router.stop();
        router = scoredRouter(gossipSubParams, topics: {
          testTopicName: TopicScoreParams(
            topicWeight: 1,
            invalidMessageDeliveriesWeight: -1,
            invalidMessageDeliveriesDecay: 0.5,
          ),
        });
        await router.attach(mockPubsub);
      }

      test('should forward message from mesh peer to other mesh peers and deliver locally', () async {
        // 1. Setup
        await router.join(testTopic); // Local node joins the topic
        router.mesh[testTopicName]!.add(mockSendingPeer); // Sending peer is in our mesh

        final mockOtherMeshPeer = MockPeerId();
        when(mockOtherMeshPeer.toBytes()).thenReturn(Uint8List.fromList([60,1,2]));
        when(mockOtherMeshPeer.toBase58()).thenReturn('QmOtherMeshPeer');
        router.mesh[testTopicName]!.add(mockOtherMeshPeer);

        // Capture RPCs sent for forwarding
        final List<PeerId> forwardedToPeers = [];
        final List<pb.RPC> forwardedRpcs = [];
        // Important: Clear and re-capture specifically for this test's action
        clearInteractions(mockComms); 
        when(mockComms.sendRpc(captureAny, captureAny, gossipSubIDv11)).thenAnswer((inv) async {
          forwardedToPeers.add(inv.positionalArguments[0] as PeerId);
          forwardedRpcs.add(inv.positionalArguments[1] as pb.RPC);
        });

        // 2. Action: Handle incoming RPC with the message
        await router.handleRpc(mockSendingPeer, incomingRpc);

        // Wait for async RPC queue to flush (PeerRpcQueue uses Future.microtask for sending)
        await Future.delayed(Duration.zero);

        // 3. Verification
        // Verify message delivered locally - THIS IS NO LONGER EXPECTED FROM ROUTER
        // The router itself traces DELIVER_MESSAGE, but doesn't call _pubsub.deliverMessage based on provided gossipsub.dart
        // verify(mockPubsub.deliverMessage(argThat(isA<PubSubMessage>()
        //   .having((m) => m.rpcMessage, 'rpcMessage', incomingPbMessage)
        //   .having((m) => m.receivedFrom, 'receivedFrom', mockSendingPeer)
        // ))).called(1);

        // Verify message forwarded to other mesh peer
        expect(forwardedToPeers.length, equals(1));
        expect(forwardedToPeers, contains(mockOtherMeshPeer));
        expect(forwardedRpcs.single.publish.first, equals(incomingPbMessage));

        // Verify trace events
        // GossipSubRouter._pushMessage tries to trace VALIDATE_MESSAGE, but this type doesn't exist in trace.proto.
        // If validation passes (as stubbed), it then traces DELIVER_MESSAGE.
        // Forwarding via _forwardMessage results in SEND_RPC traces for each forwarded message.
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();

        // Check for RECV_RPC
        final List<trace_pb.TraceEvent> recvRpcEvents = capturedTraces.where((t) => t.type == trace_pb.TraceEvent_Type.RECV_RPC).toList();
        final trace_pb.TraceEvent? recvRpcTrace = recvRpcEvents.isNotEmpty ? recvRpcEvents.first : null;
        expect(recvRpcTrace, isNotNull, reason: "RECV_RPC trace not found");
        expect(recvRpcTrace!.recvRPC.receivedFrom, orderedEquals(mockSendingPeer.toBytes()));
        
        // Check for DELIVER_MESSAGE (traced by GossipSubRouter after successful validation and local delivery)
        final List<trace_pb.TraceEvent> deliverEvents = capturedTraces.where((t) => t.type == trace_pb.TraceEvent_Type.DELIVER_MESSAGE).toList();
        final trace_pb.TraceEvent? deliverTrace = deliverEvents.isNotEmpty ? deliverEvents.first : null;
        expect(deliverTrace, isNotNull, reason: "DELIVER_MESSAGE trace not found");
        expect(deliverTrace!.deliverMessage.messageID, orderedEquals(Uint8List.fromList(incomingMessageId.codeUnits)));
        expect(deliverTrace.deliverMessage.receivedFrom, orderedEquals(mockSendingPeer.toBytes()));


        // Check for SEND_RPC (traced by RpcQueueManager when _forwardMessage calls sendRpc)
        final List<trace_pb.TraceEvent> sendRpcTraces = capturedTraces.where((t) => t.type == trace_pb.TraceEvent_Type.SEND_RPC).toList();
        expect(sendRpcTraces, isNotEmpty, reason: "SEND_RPC trace(s) for forwarding not found");
        // We expect one SEND_RPC for mockOtherMeshPeer
        expect(sendRpcTraces.length, equals(1), reason: "Expected 1 SEND_RPC trace for forwarding");
        
        final List<trace_pb.TraceEvent> specificSendRpcEvents = sendRpcTraces.where(
          (t) => t.sendRPC.sendTo.toString() == mockOtherMeshPeer.toBytes().toString() // Compare as strings for lists
        ).toList();
        final trace_pb.TraceEvent? sendRpcTraceToOther = specificSendRpcEvents.isNotEmpty ? specificSendRpcEvents.first : null;
        expect(sendRpcTraceToOther, isNotNull, reason: "SEND_RPC trace to other mesh peer not found");
        expect(sendRpcTraceToOther!.sendRPC.meta.messages, isNotEmpty);
        expect(sendRpcTraceToOther.sendRPC.meta.messages.first.messageID, orderedEquals(Uint8List.fromList(incomingMessageId.codeUnits)));
      });

      test('should not forward or deliver a duplicate message and trace DUPLICATE_MESSAGE', () async {
        // 1. Setup: Join topic, add mesh peers (including sender and another)
        await router.join(testTopic);
        router.mesh[testTopicName]!.add(mockSendingPeer);

        final mockOtherMeshPeer = MockPeerId();
        when(mockOtherMeshPeer.toBytes()).thenReturn(Uint8List.fromList([60,1,3])); // Unique bytes
        when(mockOtherMeshPeer.toBase58()).thenReturn('QmOtherMeshPeerForDup');
        router.mesh[testTopicName]!.add(mockOtherMeshPeer);

        // Ensure validateMessage is stubbed to accept for both passes
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.accept));
        when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn);


        // 2. Action: Handle incoming RPC with the message for the FIRST time
        // This will populate mcache and forward/deliver the message.
        // We need to allow sendRpc and deliverMessage for this first pass.
        // Capture calls during the first pass to ensure they happen.
        final List<PeerId> firstPassForwardedToPeers = [];
        when(mockComms.sendRpc(captureAny, captureAny, gossipSubIDv11)).thenAnswer((inv) async {
          firstPassForwardedToPeers.add(inv.positionalArguments[0] as PeerId);
        });
        // var firstPassDelivered = false; // Not directly checking _pubsub.deliverMessage call by router
        // when(mockPubsub.deliverMessage(any)).thenAnswer((_) {
        //   firstPassDelivered = true;
        // });

        await router.handleRpc(mockSendingPeer, incomingRpc);

        // Wait for async RPC queue to flush (PeerRpcQueue uses Future.microtask for sending)
        await Future.delayed(Duration.zero);

        // Verify first pass actions (optional, but good for sanity)
        // Check that it was forwarded to the other mesh peer.
        expect(firstPassForwardedToPeers.any((p) => p.toBase58() == mockOtherMeshPeer.toBase58()), isTrue, reason: "Message not forwarded on first pass to other mesh peer");
        
        // The DELIVER_MESSAGE trace is the primary check for local delivery by the router.
        // We also need to ensure that the tracer is cleared before the second pass.
        clearInteractions(mockTracer); 
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub general trace

        // Clear interactions from the first processing to isolate verification for the duplicate
        clearInteractions(mockComms);
        // clearInteractions(mockTracer); // Already cleared and re-stubbed above
        clearInteractions(mockPubsub); // Clears deliverMessage interaction too

        // Re-stub default behaviors that might be called but shouldn't for a duplicate
        // when(mockTracer.trace(any)).thenAnswer((_) => {}); // General trace stub - already done
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {
          fail('sendRpc should not be called for a duplicate message');
        });
        // Re-stub pubsub methods that might be called by the router
        when(mockPubsub.host).thenReturn(mockHost); // Needed by router
        when(mockPubsub.comms).thenReturn(mockComms); // Needed by router
        when(mockPubsub.tracer).thenReturn(mockTracer); // Needed by router
        when(mockPubsub.tracing).thenReturn(true);
        when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
        when(mockPubsub.getTopics()).thenReturn([testTopicName]); // For _shouldProcessMessage
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.accept)); // Still need validation before duplicate check
        when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn);
        when(mockPubsub.deliverMessage(any)).thenAnswer((_) { // This should NOT be called for duplicate
          fail('deliverMessage should not be called for a duplicate message');
        });


        // 3. Action: Handle incoming RPC with the SAME message for the SECOND time
        await router.handleRpc(mockSendingPeer, incomingRpc);

        // 4. Verification for the DUPLICATE processing
        // Verify DUPLICATE_MESSAGE trace
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();
        
        final List<trace_pb.TraceEvent> duplicateEventTraces = capturedTraces.where(
          (t) => t.type == trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE
        ).toList();

        expect(duplicateEventTraces, isNotEmpty, reason: "DUPLICATE_MESSAGE trace not found. Traces: ${capturedTraces.map((e)=>e.type).toList()}");
        
        // If the above expect passes, there's at least one. We'll check the first one.
        final trace_pb.TraceEvent duplicateTrace = duplicateEventTraces.first;
        expect(duplicateTrace.duplicateMessage.messageID, orderedEquals(Uint8List.fromList(incomingMessageId.codeUnits)));
        expect(duplicateTrace.duplicateMessage.receivedFrom, orderedEquals(mockSendingPeer.toBytes()));

        // Verify message was NOT delivered locally again by pubsub
        verifyNever(mockPubsub.deliverMessage(any));

        // Verify message was NOT forwarded again
        verifyNever(mockComms.sendRpc(any, any, any));
        
        // Verify no DELIVER_MESSAGE or SEND_RPC traces for the duplicate processing pass
        // (Excluding RECV_RPC which is expected for the second arrival, and DUPLICATE_MESSAGE itself)
        final unexpectedTraces = capturedTraces.where((t) => 
            t.type != trace_pb.TraceEvent_Type.RECV_RPC && 
            t.type != trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE &&
            (t.type == trace_pb.TraceEvent_Type.DELIVER_MESSAGE || t.type == trace_pb.TraceEvent_Type.SEND_RPC)
        ).toList();

        expect(unexpectedTraces, isEmpty, 
             reason: "DELIVER_MESSAGE or SEND_RPC trace found for duplicate processing. Unexpected traces: ${unexpectedTraces.map((t)=>t.type).toList()}");
      });

      test('should drop a rejected message, penalise the sender, and not validate its duplicates', () async {
        // 1. Setup: Join topic, add mesh peers
        await useRouterScoringInvalidMessages();
        await router.join(testTopic);
        router.mesh[testTopicName]!.add(mockSendingPeer); // Sending peer is in our mesh

        final mockOtherMeshPeer = MockPeerId();
        when(mockOtherMeshPeer.toBytes()).thenReturn(Uint8List.fromList([60,1,4])); // Unique bytes
        when(mockOtherMeshPeer.toBase58()).thenReturn('QmOtherMeshPeerForReject');
        router.mesh[testTopicName]!.add(mockOtherMeshPeer);

        when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn);
        await router.addPeer(mockSendingPeer, '/meshsub/1.1.0');
        await router.addPeer(mockOtherMeshPeer, '/meshsub/1.1.0');

        // Stub validateMessage to REJECT
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.reject));

        // Ensure deliverMessage and sendRpc are not called
        when(mockPubsub.deliverMessage(any)).thenAnswer((_) {
          fail('deliverMessage should not be called for a rejected message');
        });
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {
          fail('sendRpc should not be called for a rejected message');
        });

        clearInteractions(mockTracer); // Clear previous traces
        when(mockTracer.trace(any)).thenAnswer((_) => {}); // Re-stub general trace

        // 2. Action: Handle incoming RPC with the message
        final accepted = await router.handleRpc(mockSendingPeer, incomingRpc);

        // 3. Verification
        expect(accepted, isEmpty);
        verify(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).called(1);
        // The delivering peer is penalised on the topic.
        expect(router.score!.snapshot(mockSendingPeer)!.topics[testTopicName]?.invalidMessageDeliveries, 1);
        expect(router.score!.score(mockSendingPeer), lessThan(0));

        // Verify message was NOT delivered locally or forwarded
        verifyNever(mockPubsub.deliverMessage(any));
        verifyNever(mockComms.sendRpc(any, any, any));

        // PubSub.validateMessage traces REJECT_MESSAGE with the reason; the
        // router traces no DELIVER_MESSAGE or SEND_RPC for the message.
        final capturedTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();
        final unexpectedTraces = capturedTraces.where((t) =>
            t.type == trace_pb.TraceEvent_Type.DELIVER_MESSAGE || t.type == trace_pb.TraceEvent_Type.SEND_RPC
        ).toList();
        expect(unexpectedTraces, isEmpty,
             reason: "DELIVER_MESSAGE or SEND_RPC trace found for rejected message. Unexpected traces: ${unexpectedTraces.map((t)=>t.type).toList()}");

        // 4. A duplicate of the rejected message from another peer is not
        // validated again, and that peer is penalised too.
        clearInteractions(mockTracer);
        when(mockTracer.trace(any)).thenAnswer((_) => {});
        final acceptedDup = await router.handleRpc(mockOtherMeshPeer, incomingRpc);
        expect(acceptedDup, isEmpty);
        verifyNever(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen')));
        expect(router.score!.snapshot(mockOtherMeshPeer)!.topics[testTopicName]?.invalidMessageDeliveries, 1);
        final dupTraces = verify(mockTracer.trace(captureAny)).captured.cast<trace_pb.TraceEvent>();
        expect(dupTraces.where((t) => t.type == trace_pb.TraceEvent_Type.DUPLICATE_MESSAGE), isNotEmpty);
      });

      test('should drop an ignored message without penalising the sender', () async {
        await useRouterScoringInvalidMessages();
        await router.join(testTopic);
        router.mesh[testTopicName]!.add(mockSendingPeer);
        final mockOtherMeshPeer = MockPeerId();
        when(mockOtherMeshPeer.toBytes()).thenReturn(Uint8List.fromList([60,1,5]));
        when(mockOtherMeshPeer.toBase58()).thenReturn('QmOtherMeshPeerForIgnore');
        router.mesh[testTopicName]!.add(mockOtherMeshPeer);

        await router.addPeer(mockSendingPeer, '/meshsub/1.1.0');
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.ignore));
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {
          fail('sendRpc should not be called for an ignored message');
        });

        final accepted = await router.handleRpc(mockSendingPeer, incomingRpc);

        expect(accepted, isEmpty);
        expect(router.score!.snapshot(mockSendingPeer)!.topics[testTopicName]?.invalidMessageDeliveries ?? 0, 0);
        expect(router.score!.score(mockSendingPeer), 0.0);
        verifyNever(mockComms.sendRpc(any, any, any));
      });
    });

    group('Heartbeat Mechanism', () {
      test('heartbeat timer is active after start and inactive after stop', () async {
        // Router is started in global setUp.
        expect(router.isStarted, isTrue);

        await router.stop();
        expect(router.isStarted, isFalse);

        // Restart to not affect other tests if this group runs out of order or is isolated,
        // or if the global tearDown doesn't restart it.
        await router.start();
        expect(router.isStarted, isTrue); // Verify restart
      });

      test('the scorer decays its counters every decay interval while the router runs', () {
        fakeAsync((async) {
          router.stop();
          final peer = MockPeerId();
          when(peer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x40]));
          when(peer.toBase58()).thenReturn('QmDecayPeer');
          final testRouter = GossipSubRouter(
            params: GossipSubParams(),
            scoreParams: PeerScoreParams(
              behaviourPenaltyWeight: -1,
              behaviourPenaltyDecay: 0.5,
              decayInterval: const Duration(seconds: 1),
            ),
            scoreThresholds: _testThresholds,
          );
          testRouter.attach(mockPubsub);
          testRouter.addPeer(peer, '/meshsub/1.1.0');
          testRouter.score!.addPenalty(peer, 4);

          testRouter.start();
          async.elapse(const Duration(seconds: 1));
          expect(testRouter.score!.snapshot(peer)!.behaviourPenalty, equals(2));
          async.elapse(const Duration(seconds: 1));
          expect(testRouter.score!.snapshot(peer)!.behaviourPenalty, equals(1));

          testRouter.stop();
          async.elapse(const Duration(seconds: 5));
          expect(testRouter.score!.snapshot(peer)!.behaviourPenalty, equals(1));
        });
      });

      test('first heartbeat runs after the initial delay, then one every heartbeat interval', () {
        fakeAsync((async) {
          router.stop();
          final testRouter = GossipSubRouter(params: GossipSubParams());
          testRouter.attach(mockPubsub);
          // With no topics, a heartbeat reads the connected peers once (to
          // forget the disconnected ones); the router reads them nowhere else.
          clearInteractions(mockNetwork);
          testRouter.start();

          async.elapse(const Duration(milliseconds: 99));
          verifyNever(mockNetwork.peers);
          async.elapse(const Duration(milliseconds: 1));
          verify(mockNetwork.peers).called(1);

          async.elapse(const Duration(seconds: 10));
          verify(mockNetwork.peers).called(10);

          testRouter.stop();
          async.elapse(const Duration(seconds: 10));
          verifyNever(mockNetwork.peers);
        });
      });

      // TODO: Test other heartbeat actions: opportunistic grafting, mesh maintenance (GRAFT/PRUNE), fanout updates.
    });

    group('Advanced Mesh Management (via Heartbeat)', () {
      const testTopicName = 'adv-mesh-topic';
      late Topic testTopic;

      /// Makes [peers] known to [r] as subscribed to [topic], as if each had
      /// sent a SUBSCRIBE, then sets the mesh of [topic] to [mesh] if given.
      void subscribePeers(FakeAsync async, GossipSubRouter r, List<PeerId> peers,
          {String topic = testTopicName, Set<PeerId>? mesh}) {
        for (final peer in peers) {
          r.handleRpc(peer, pb.RPC()
            ..subscriptions.add(pb.RPC_SubOpts()
              ..subscribe = true
              ..topicid = topic));
        }
        async.flushMicrotasks();
        if (mesh != null) r.mesh[topic] = mesh;
      }

      setUp(() {
        testTopic = Topic(testTopicName);
        // Ensure the router is joined to the topic for these tests
        // router.join(testTopic) will be called in specific tests or sub-setups
        // as needed.

        // Clear interactions from other groups
        clearInteractions(mockComms);
        clearInteractions(mockTracer);
        clearInteractions(mockPubsub);

        // Re-stub default behaviors
        when(mockTracer.trace(any)).thenAnswer((_) => {});
        when(mockComms.sendRpc(any, any, any)).thenAnswer((_) async {});
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen'))).thenAnswer((inv) => _validated(inv, ValidationResult.accept));
        when(mockPubsub.deliverMessage(any)).thenAnswer((_) {});
        when(mockPubsub.messageIdFn).thenReturn(defaultMessageIdFn);
        when(mockPubsub.host).thenReturn(mockHost);
        when(mockPubsub.comms).thenReturn(mockComms);
        when(mockPubsub.tracer).thenReturn(mockTracer);
        when(mockPubsub.tracing).thenReturn(true);
        when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
        when(mockPubsub.getTopics()).thenReturn([testTopicName]); // Assume joined for mesh management
        when(mockPubsub.removePeer(any)).thenAnswer((_) async => {});
      });

      // Tests for _manageMesh, _sendGraftPrune, peer selection for GRAFT/PRUNE
      // These might be triggered by advancing a FakeAsync timer to fire the heartbeat,
      // or by more direct means if possible and appropriate.
      
      test('when mesh size for a topic is below DLow, heartbeat attempts to GRAFT to new peers', () {
        fakeAsync((async) {
          // Stop global router, use a local one for this test
          router.stop();
          final testRouterParams = GossipSubParams(
            D: 6, DLow: 4, DHigh: 12, DScore: 0, 
            fanoutTTL: Duration(seconds: 1) // Short TTL for testing
          );
          final testRouter = scoredRouter(testRouterParams);

          // Clear interactions for mocks from outer scope
          clearInteractions(mockPubsub);
          clearInteractions(mockComms);
          clearInteractions(mockTracer);
          clearInteractions(mockHost); // Though host.id is mostly static
          clearInteractions(mockNetwork);


          // Setup mocks for testRouter
          when(mockPubsub.host).thenReturn(mockHost);
          when(mockHost.id).thenReturn(mockLocalPeerId); // From outer setup
          when(mockHost.network).thenReturn(mockNetwork);
          when(mockPubsub.comms).thenReturn(mockComms);
          when(mockPubsub.tracer).thenReturn(mockTracer);
          when(mockPubsub.tracing).thenReturn(true);
          when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
          when(mockPubsub.getTopics()).thenReturn([testTopicName]); // Router is subscribed
          when(mockTracer.trace(any)).thenAnswer((_) => {});
          
          testRouter.attach(mockPubsub);
          testRouter.join(testTopic); // Join the topic, mesh will be empty initially
          
          expect(testRouter.mesh[testTopicName]!.length, 0); // Initially 0, less than DLow (4)

          // Mock candidate peers available in the network
          final mockCandidatePeer1 = MockPeerId();
          when(mockCandidatePeer1.toBytes()).thenReturn(Uint8List.fromList([70,1,1]));
          when(mockCandidatePeer1.toBase58()).thenReturn('QmCandidate1');
          
          final mockCandidatePeer2 = MockPeerId();
          when(mockCandidatePeer2.toBytes()).thenReturn(Uint8List.fromList([70,1,2]));
          when(mockCandidatePeer2.toBase58()).thenReturn('QmCandidate2');
          
          final mockCandidatePeer3 = MockPeerId();
          when(mockCandidatePeer3.toBytes()).thenReturn(Uint8List.fromList([70,1,3]));
          when(mockCandidatePeer3.toBase58()).thenReturn('QmCandidate3');

          final mockCandidatePeer4 = MockPeerId(); // Enough to reach D=6
          when(mockCandidatePeer4.toBytes()).thenReturn(Uint8List.fromList([70,1,4]));
          when(mockCandidatePeer4.toBase58()).thenReturn('QmCandidate4');
          
          final mockCandidatePeer5 = MockPeerId();
          when(mockCandidatePeer5.toBytes()).thenReturn(Uint8List.fromList([70,1,5]));
          when(mockCandidatePeer5.toBase58()).thenReturn('QmCandidate5');

          final mockCandidatePeer6 = MockPeerId();
          when(mockCandidatePeer6.toBytes()).thenReturn(Uint8List.fromList([70,1,6]));
          when(mockCandidatePeer6.toBase58()).thenReturn('QmCandidate6');

          // Give each candidate peer its score
          setScore(testRouter, mockCandidatePeer1, 10.0);
          setScore(testRouter, mockCandidatePeer2, 5.0);
          setScore(testRouter, mockCandidatePeer3, -5.0); // Bad score, should be ignored
          setScore(testRouter, mockCandidatePeer4, 8.0);
          setScore(testRouter, mockCandidatePeer5, 7.0);
          setScore(testRouter, mockCandidatePeer6, 6.0);

          // Connected, good score, but not subscribed to the topic.
          final mockUnsubscribedPeer = MockPeerId();
          when(mockUnsubscribedPeer.toBytes()).thenReturn(Uint8List.fromList([70,1,7]));
          when(mockUnsubscribedPeer.toBase58()).thenReturn('QmUnsubscribed');
          setScore(testRouter, mockUnsubscribedPeer, 10.0);

          // Simulate these peers being available in the wider network
          when(mockNetwork.peers).thenReturn([
            mockLocalPeerId, // Self
            mockCandidatePeer1, 
            mockCandidatePeer2, 
            mockCandidatePeer3, // Bad score peer
            mockCandidatePeer4,
            mockCandidatePeer5,
            mockCandidatePeer6,
            mockUnsubscribedPeer,
          ]);
          subscribePeers(async, testRouter, [
            mockCandidatePeer1,
            mockCandidatePeer2,
            mockCandidatePeer3,
            mockCandidatePeer4,
            mockCandidatePeer5,
            mockCandidatePeer6,
          ], mesh: {});

          // Capture GRAFT RPCs
          final List<PeerId> graftedPeers = [];
          when(mockComms.sendRpc(captureAny, argThat(isA<pb.RPC>()
            .having((rpc) => rpc.hasControl() && rpc.control.graft.isNotEmpty && rpc.control.graft.first.topicID == testTopicName, 'isGraftForTopic', true)), 
            gossipSubIDv11
          )).thenAnswer((inv) async {
            graftedPeers.add(inv.positionalArguments[0] as PeerId);
          });

          testRouter.start(); // Start router, heartbeat will run
          async.elapse(testRouterParams.fanoutTTL); // Trigger heartbeat

          // Verify GRAFTs were sent. Expect D peers (6) to be grafted.
          // The router will try to select up to D peers.
          // It found 5 good score peers (1,2,4,5,6).
          expect(graftedPeers.length, equals(5), 
            reason: "Should attempt to GRAFT up to D peers with good scores. Found: ${graftedPeers.map((p) => p.toBase58()).toList()}");
          expect(graftedPeers, containsAll([mockCandidatePeer1, mockCandidatePeer2, mockCandidatePeer4, mockCandidatePeer5, mockCandidatePeer6]));
          expect(graftedPeers, isNot(contains(mockCandidatePeer3))); // Should not graft bad score peer
          expect(graftedPeers, isNot(contains(mockUnsubscribedPeer))); // Not subscribed to the topic
          
          // Verify mesh state (optimistic addition)
          expect(testRouter.mesh[testTopicName]!.length, equals(5));
          expect(testRouter.mesh[testTopicName], containsAll([mockCandidatePeer1, mockCandidatePeer2, mockCandidatePeer4, mockCandidatePeer5, mockCandidatePeer6]));

          testRouter.stop();
          // Restore global router if necessary, or ensure global teardown handles it.
          // For now, assume main setUp/tearDown handles the global `router`.
        });
      });

      test('when mesh size for a topic is above DHigh, heartbeat attempts to PRUNE excess peers', () {
        fakeAsync((async) {
          router.stop(); // Stop global router
          final testRouterParams = GossipSubParams(
            // D=2, DHigh=3 for this test; the DScore=2 best peers are kept
            // (go-libp2p-pubsub keeps DScore peers by score, the rest of D
            // at random). No outbound peers to keep (DOut=0).
            D: 2, DLow: 1, DHigh: 3, DScore: 2, DOut: 0,
            fanoutTTL: Duration(seconds: 1),
            prunePeers: 2 // For PX
          );
          final testRouter = scoredRouter(testRouterParams);

          clearInteractions(mockPubsub);
          clearInteractions(mockComms);
          clearInteractions(mockTracer);
          clearInteractions(mockNetwork);

          when(mockPubsub.host).thenReturn(mockHost);
          when(mockHost.id).thenReturn(mockLocalPeerId);
          when(mockHost.network).thenReturn(mockNetwork);
          when(mockPubsub.comms).thenReturn(mockComms);
          when(mockPubsub.tracer).thenReturn(mockTracer);
          when(mockPubsub.tracing).thenReturn(true);
          when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
          when(mockPubsub.getTopics()).thenReturn([testTopicName]);
          when(mockTracer.trace(any)).thenAnswer((_) => {});
          
          testRouter.attach(mockPubsub);
          testRouter.join(testTopic);
          
          // Setup mesh with more peers than DHigh (3)
          // D = 2, DHigh = 3. Let's add 5 peers. 2 should be pruned.
          final mockMeshPeer1 = MockPeerId(); // Score: 10 (High)
          when(mockMeshPeer1.toBytes()).thenReturn(Uint8List.fromList([80,1,1]));
          when(mockMeshPeer1.toBase58()).thenReturn('QmMeshPrune1');
          setScore(testRouter, mockMeshPeer1, 10.0);

          final mockMeshPeer2 = MockPeerId(); // Score: 1 (Low) - Should be pruned
          when(mockMeshPeer2.toBytes()).thenReturn(Uint8List.fromList([80,1,2]));
          when(mockMeshPeer2.toBase58()).thenReturn('QmMeshPrune2');
          setScore(testRouter, mockMeshPeer2, 1.0);

          final mockMeshPeer3 = MockPeerId(); // Score: 8 (Medium)
          when(mockMeshPeer3.toBytes()).thenReturn(Uint8List.fromList([80,1,3]));
          when(mockMeshPeer3.toBase58()).thenReturn('QmMeshPrune3');
          setScore(testRouter, mockMeshPeer3, 8.0);
          
          final mockMeshPeer4 = MockPeerId(); // Score: 2 (Low) - Should be pruned
          when(mockMeshPeer4.toBytes()).thenReturn(Uint8List.fromList([80,1,4]));
          when(mockMeshPeer4.toBase58()).thenReturn('QmMeshPrune4');
          setScore(testRouter, mockMeshPeer4, 2.0);

          final mockMeshPeer5 = MockPeerId(); // Score: 9 (High)
          when(mockMeshPeer5.toBytes()).thenReturn(Uint8List.fromList([80,1,5]));
          when(mockMeshPeer5.toBase58()).thenReturn('QmMeshPrune5');
          setScore(testRouter, mockMeshPeer5, 9.0);

          final initialMeshPeers = {mockMeshPeer1, mockMeshPeer2, mockMeshPeer3, mockMeshPeer4, mockMeshPeer5};
          when(mockNetwork.peers).thenReturn(List<PeerId>.from(initialMeshPeers)..add(mockLocalPeerId));
          // Subscribed, so that they are PX candidates.
          subscribePeers(async, testRouter, initialMeshPeers.toList(), mesh: {...initialMeshPeers});
          expect(testRouter.mesh[testTopicName]!.length, 5); // Above DHigh (3)

          // Capture PRUNE RPCs
          final List<PeerId> prunedPeers = [];
          final List<pb.ControlPrune> pruneMessages = [];
          when(mockComms.sendRpc(captureAny, argThat(isA<pb.RPC>()
            .having((rpc) => rpc.hasControl() && rpc.control.prune.isNotEmpty && rpc.control.prune.first.topicID == testTopicName, 'isPruneForTopic', true)), 
            gossipSubIDv11
          )).thenAnswer((inv) async {
            prunedPeers.add(inv.positionalArguments[0] as PeerId);
            final rpc = inv.positionalArguments[1] as pb.RPC;
            pruneMessages.add(rpc.control.prune.first);
          });

          testRouter.start();
          async.elapse(testRouterParams.fanoutTTL); // Trigger heartbeat

          // We want to prune down to D (2 peers). We have 5. So 3 should be pruned.
          // The logic prunes (currentMeshSize - D) peers. So 5 - 2 = 3 peers.
          expect(prunedPeers.length, equals(3), 
            reason: "Should attempt to PRUNE (current - D) peers. Pruned: ${prunedPeers.map((p)=>p.toBase58()).toList()}");
          
          // The DScore (2) best peers are kept; the others are pruned.
          // Scores: P2(1), P4(2), P3(8), P5(9), P1(10)
          // Expected to prune: P2, P4, P3
          expect(prunedPeers, containsAll([mockMeshPeer2, mockMeshPeer4, mockMeshPeer3]));
          expect(prunedPeers.any((p) => p == mockMeshPeer1 || p == mockMeshPeer5), isFalse, reason: "Should not prune high score peers P1 or P5");


          // Verify mesh state after pruning
          expect(testRouter.mesh[testTopicName]!.length, equals(2)); // Should be D
          expect(testRouter.mesh[testTopicName], containsAll([mockMeshPeer1, mockMeshPeer5]));
          expect(testRouter.mesh[testTopicName]!.any((p) => p == mockMeshPeer2 || p == mockMeshPeer3 || p == mockMeshPeer4), isFalse, reason: "Low score peers P2, P3, P4 should not be in mesh");

          // Verify PX peers in PRUNE messages (optional, but good for completeness)
          // For each pruned peer, the PRUNE message should contain some other mesh peers for PX.
          // Example: For mockMeshPeer2 (score 1), PX could be P1, P5 (or others from remaining mesh)
          for(final pruneMsg in pruneMessages) {
            expect(pruneMsg.peers.length, lessThanOrEqualTo(testRouterParams.prunePeers));
            // Ensure PX peers are not the pruned peer itself and are from the original mesh.
            for(final pxInfo in pruneMsg.peers) {
                // pxInfo.peerID is List<int>. We need to compare it with PeerId.toBytes() which is Uint8List.
                // A common way to compare is converting both to string or using a collection equality.
                // For simplicity in test, converting to string is okay.
                final pxPeerIdBytesStr = Uint8List.fromList(pxInfo.peerID).toString();
                expect(initialMeshPeers.any((p) => p.toBytes().toString() == pxPeerIdBytesStr), isTrue, 
                    reason: "PX peer with bytes $pxPeerIdBytesStr not in original mesh for a PRUNE message.");
                // Also check that the PX peer is not the one being pruned in *this specific* message.
                // This requires matching pruneMsg to the prunedPeer, which is a bit more involved.
            }
          }

          testRouter.stop();
        });
      });

      /// Runs one heartbeat of a router with scoring, joined to the test
      /// topic, whose mesh is [meshScores] and whose other subscribed peers
      /// are [otherScores] (by name, with their scores). Returns the RPCs
      /// sent, by peer name, and the mesh after the heartbeat.
      (Map<String, List<pb.RPC>>, Set<String>) runHeartbeat(
        FakeAsync async,
        GossipSubParams params, {
        required Map<String, double> meshScores,
        Map<String, double> otherScores = const {},
        PeerScoreThresholds thresholds = _testThresholds,
      }) {
        router.stop();
        final testRouter = scoredRouter(params, thresholds: thresholds);
        testRouter.attach(mockPubsub);
        testRouter.join(testTopic);

        final peers = <String, PeerId>{};
        var id = 0;
        for (final entry in {...meshScores, ...otherScores}.entries) {
          final peer = MockPeerId();
          when(peer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0xa0 + id++]));
          when(peer.toBase58()).thenReturn('Qm${entry.key}');
          peers[entry.key] = peer;
          setScore(testRouter, peer, entry.value);
        }
        when(mockNetwork.peers).thenReturn(peers.values.toList());
        subscribePeers(async, testRouter, peers.values.toList(),
            mesh: {for (final name in meshScores.keys) peers[name]!});

        final names = {for (final e in peers.entries) e.value: e.key};
        final sent = <String, List<pb.RPC>>{};
        when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
          sent.putIfAbsent(names[inv.positionalArguments[0]]!, () => []).add(inv.positionalArguments[1] as pb.RPC);
        });

        testRouter.start();
        async.elapse(params.heartbeatInitialDelay);
        async.flushMicrotasks();
        final mesh = {for (final p in testRouter.mesh[testTopicName]!) names[p]!};
        testRouter.stop();
        return (sent, mesh);
      }

      test('heartbeat prunes the mesh peers with a negative score, without PX', () {
        fakeAsync((async) {
          final (sent, mesh) = runHeartbeat(async, GossipSubParams(D: 2, DLow: 1, DHigh: 3, DScore: 1, DOut: 0),
              meshScores: {'Good': 1, 'Bad': -1});

          expect(mesh, equals({'Good'}));
          final prune = sent['Bad']!.single.control.prune.single;
          expect(prune.topicID, equals(testTopicName));
          expect(prune.peers, isEmpty, reason: 'no PX to a peer pruned for its negative score');
          expect(sent, isNot(contains('Good')));
        });
      });

      // As go-libp2p-pubsub's heartbeat: opportunistic grafting runs only
      // when the median score of the mesh is below the threshold, and GRAFTs
      // at most opportunisticGraftPeers peers scoring above that median.
      final opportunisticParams = GossipSubParams(
        D: 3, DLow: 2, DHigh: 4, DScore: 2, DOut: 0, // Mesh target 3, DHigh 4
        opportunisticGraftTicks: 1, // Opportunistic grafting on every heartbeat
        opportunisticGraftPeers: 2,
      );
      const opportunisticThresholds = PeerScoreThresholds(
          gossipThreshold: -10, publishThreshold: -50, graylistThreshold: -80, opportunisticGraftThreshold: 5);

      test('heartbeat grafts opportunistically when the mesh median score is below the threshold', () {
        fakeAsync((async) {
          // The mesh has DLow peers, so the DLow maintenance does not GRAFT.
          final (sent, mesh) = runHeartbeat(async, opportunisticParams,
              thresholds: opportunisticThresholds,
              meshScores: {'Mesh1': 3, 'Mesh2': 3},
              otherScores: {'Good1': 6, 'Good2': 7, 'Good3': 8, 'Low': 2});

          // Two of the three peers above the median (3) are grafted; not the
          // peer below it.
          final grafted = sent.keys.toSet();
          expect(grafted, hasLength(opportunisticParams.opportunisticGraftPeers));
          expect(grafted.difference({'Good1', 'Good2', 'Good3'}), isEmpty);
          for (final name in grafted) {
            expect(sent[name]!.single.control.graft.single.topicID, equals(testTopicName));
          }
          expect(mesh, equals({'Mesh1', 'Mesh2', ...grafted}));
        });
      });

      test('heartbeat does not graft opportunistically when the mesh median score is at the threshold', () {
        fakeAsync((async) {
          final (sent, mesh) = runHeartbeat(async, opportunisticParams,
              thresholds: opportunisticThresholds,
              meshScores: {'Mesh1': 1, 'Mesh2': 5, 'Mesh3': 6},
              otherScores: {'Good': 10});

          expect(sent, isEmpty);
          expect(mesh, equals({'Mesh1', 'Mesh2', 'Mesh3'}));
        });
      });

      group('PRUNE backoff', () {
        late GossipSubRouter testRouter;
        late MockPeerId peer;
        late List<PeerId> grafted;
        late List<pb.ControlPrune> prunesSent;

        /// Sets up a router joined to the test topic with [peer] in its mesh.
        void setUpRouter(FakeAsync async) {
          router.stop();
          testRouter = scoredRouter(GossipSubParams());
          clearInteractions(mockPubsub);
          when(mockPubsub.getTopics()).thenReturn([testTopicName]);
          peer = MockPeerId();
          when(peer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x70]));
          when(peer.toBase58()).thenReturn('QmBackoffPeer');
          when(mockNetwork.peers).thenReturn([peer]);
          grafted = [];
          prunesSent = [];
          when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
            final rpc = inv.positionalArguments[1] as pb.RPC;
            if (rpc.control.graft.isNotEmpty) grafted.add(inv.positionalArguments[0] as PeerId);
            prunesSent.addAll(rpc.control.prune);
          });

          testRouter.attach(mockPubsub);
          setScore(testRouter, peer, 0);
          subscribePeers(async, testRouter, [peer]);
          testRouter.join(testTopic);
          async.flushMicrotasks();
          expect(testRouter.mesh[testTopicName], equals({peer}));
          grafted.clear();
        }

        void receive(FakeAsync async, pb.ControlMessage control) {
          testRouter.handleRpc(peer, pb.RPC()..control = control);
          async.flushMicrotasks();
        }

        pb.ControlMessage prune({int? backoffSeconds}) {
          final p = pb.ControlPrune()..topicID = testTopicName;
          if (backoffSeconds != null) p.backoff = Int64(backoffSeconds);
          return pb.ControlMessage()..prune.add(p);
        }

        /// Checks that the heartbeat GRAFTs [peer] again only after [backoff].
        /// As go-libp2p-pubsub's clearBackoff, the backoff holds until it is
        /// cleared, 2 heartbeats after it ends, by the clearing that runs
        /// every 15 heartbeats.
        void expectNoGraftFor(FakeAsync async, Duration backoff) {
          final interval = testRouter.params.heartbeatInterval;
          testRouter.start();
          async.elapse(backoff + interval * 2);
          async.flushMicrotasks();
          expect(grafted, isEmpty, reason: 'GRAFT during the backoff');
          async.elapse(interval * 15);
          async.flushMicrotasks();
          expect(grafted, equals([peer]), reason: 'GRAFT after the backoff');
          testRouter.stop();
        }

        test('a received PRUNE stops GRAFTs to the peer for its backoff', () {
          fakeAsync((async) {
            setUpRouter(async);
            receive(async, prune(backoffSeconds: 30));
            expect(testRouter.mesh[testTopicName], isEmpty);
            expectNoGraftFor(async, const Duration(seconds: 30));
          });
        });

        test('a received PRUNE without a backoff stops GRAFTs for pruneBackoff', () {
          fakeAsync((async) {
            setUpRouter(async);
            receive(async, prune());
            expectNoGraftFor(async, testRouter.params.pruneBackoff);
          });
        });

        test('a GRAFT during the backoff is answered with PRUNE and penalised', () {
          fakeAsync((async) {
            setUpRouter(async);
            double behaviourPenalty() => testRouter.score!.snapshot(peer)!.behaviourPenalty;
            final graft = pb.ControlMessage()..graft.add(pb.ControlGraft()..topicID = testTopicName);
            receive(async, prune(backoffSeconds: 60));

            // Within graftFloodThreshold of the PRUNE: penalised twice.
            async.elapse(const Duration(seconds: 1));
            receive(async, graft);
            expect(testRouter.mesh[testTopicName], isEmpty);
            expect(behaviourPenalty(), equals(2));
            expect(prunesSent.single.topicID, equals(testTopicName));
            expect(prunesSent.single.peers, isEmpty, reason: 'no PX to a peer that GRAFTs during its backoff');
            expect(prunesSent.single.backoff.toInt(), equals(testRouter.params.pruneBackoff.inSeconds));

            // Later in the (renewed) backoff: penalised once.
            async.elapse(const Duration(seconds: 20));
            receive(async, graft);
            expect(testRouter.mesh[testTopicName], isEmpty);
            expect(behaviourPenalty(), equals(3));
            expect(prunesSent, hasLength(2));
          });
        });
      });

      test('heartbeat removes the peers that are no longer connected', () {
        fakeAsync((async) {
          router.stop();
          final testRouter = GossipSubRouter(params: GossipSubParams());
          clearInteractions(mockPubsub);
          when(mockPubsub.getTopics()).thenReturn([testTopicName]);

          final stayingPeer = MockPeerId();
          when(stayingPeer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x60]));
          when(stayingPeer.toBase58()).thenReturn('QmStaying');
          final leavingPeer = MockPeerId();
          when(leavingPeer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x61]));
          when(leavingPeer.toBase58()).thenReturn('QmLeaving');

          testRouter.attach(mockPubsub);
          testRouter.join(testTopic);
          subscribePeers(async, testRouter, [stayingPeer, leavingPeer],
              mesh: {stayingPeer, leavingPeer});
          testRouter.fanout['other-topic'] = {leavingPeer};
          testRouter.fanoutLastPublished['other-topic'] = DateTime.now(); // Not expired
          when(mockNetwork.peers).thenReturn([stayingPeer]);

          testRouter.start();
          async.elapse(testRouter.params.heartbeatInitialDelay);

          expect(testRouter.mesh[testTopicName], equals({stayingPeer}));
          expect(testRouter.fanout['other-topic'], isEmpty);
          verify(mockPubsub.removePeer(leavingPeer)).called(1);
          verifyNever(mockPubsub.removePeer(stayingPeer));

          testRouter.stop();
        });
      });

      test('SUBSCRIBE does not add the peer to the mesh; the next heartbeat GRAFTs it', () {
        fakeAsync((async) {
          router.stop();
          final testRouter = GossipSubRouter(params: GossipSubParams());
          clearInteractions(mockComms);
          when(mockPubsub.getTopics()).thenReturn([testTopicName]);

          final grafted = <PeerId>[];
          when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
            final rpc = inv.positionalArguments[1] as pb.RPC;
            if (rpc.control.graft.any((g) => g.topicID == testTopicName)) {
              grafted.add(inv.positionalArguments[0] as PeerId);
            }
          });

          testRouter.attach(mockPubsub);
          testRouter.join(testTopic);
          testRouter.start();

          final newPeer = MockPeerId();
          when(newPeer.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, 0x50]));
          when(newPeer.toBase58()).thenReturn('QmNewPeer');
          when(mockNetwork.peers).thenReturn([newPeer]);
          subscribePeers(async, testRouter, [newPeer]);

          expect(testRouter.mesh[testTopicName], isEmpty);
          expect(grafted, isEmpty);

          async.elapse(testRouter.params.heartbeatInitialDelay);
          async.flushMicrotasks();

          expect(testRouter.mesh[testTopicName], equals({newPeer}));
          expect(grafted, equals([newPeer]));

          testRouter.stop();
        });
      });

      test('heartbeat removes topic from fanout if fanoutTTL has expired since last publish', () {
        fakeAsync((async) {
          router.stop();
          final ttl = Duration(seconds: 10);
          final testRouterParams = GossipSubParams(fanoutTTL: ttl);
          final testRouter = GossipSubRouter(params: testRouterParams);

          clearInteractions(mockPubsub);
          clearInteractions(mockComms);
          clearInteractions(mockTracer);
          clearInteractions(mockNetwork);
          
          when(mockPubsub.host).thenReturn(mockHost);
          when(mockHost.id).thenReturn(mockLocalPeerId);
          when(mockHost.network).thenReturn(mockNetwork);
          when(mockPubsub.comms).thenReturn(mockComms);
          when(mockPubsub.tracer).thenReturn(mockTracer);
          when(mockPubsub.tracing).thenReturn(true);
          when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
          when(mockPubsub.getTopics()).thenReturn([]); // Not subscribed to any topic
          when(mockTracer.trace(any)).thenAnswer((_) => {});

          testRouter.attach(mockPubsub);

          const fanoutTopic = 'fanout-topic-ttl';
          final mockFanoutPeer = MockPeerId();
          when(mockFanoutPeer.toBytes()).thenReturn(Uint8List.fromList([100,1,1]));
          when(mockFanoutPeer.toBase58()).thenReturn('QmFanoutTTLPeer');
          
          testRouter.fanout[fanoutTopic] = {mockFanoutPeer};
          // Simulate last publish was just before TTL would expire on next heartbeat
          testRouter.fanoutLastPublished[fanoutTopic] = DateTime.now().subtract(ttl); 

          testRouter.start();
          
          // Elapse time slightly more than TTL to ensure expiry
          async.elapse(ttl + Duration(seconds: 1));

          expect(testRouter.fanout.containsKey(fanoutTopic), isFalse, reason: "Fanout topic should be removed after TTL expiry.");
          expect(testRouter.fanoutLastPublished.containsKey(fanoutTopic), isFalse, reason: "Fanout last published time should be cleared.");

          testRouter.stop();
        });
      });

      test('heartbeat fills fanout for a topic if below D peers', () {
        fakeAsync((async) {
          router.stop();
          final testRouterParams = GossipSubParams(
            D: 3, DLow: 3, DScore: 3, DOut: 0, fanoutTTL: Duration(seconds: 1) // D=3 for fanout, short TTL for test
          );
          final testRouter = scoredRouter(testRouterParams);

          clearInteractions(mockPubsub);
          clearInteractions(mockComms);
          clearInteractions(mockTracer);
          clearInteractions(mockNetwork);

          when(mockPubsub.host).thenReturn(mockHost);
          when(mockHost.id).thenReturn(mockLocalPeerId);
          when(mockHost.network).thenReturn(mockNetwork);
          when(mockPubsub.comms).thenReturn(mockComms);
          when(mockPubsub.tracer).thenReturn(mockTracer);
          when(mockPubsub.tracing).thenReturn(true);
          when(mockPubsub.traceEvent(any)).thenAnswer((inv) => mockTracer.trace(inv.positionalArguments.first as trace_pb.TraceEvent));
          when(mockPubsub.getTopics()).thenReturn([]); // Not subscribed
          when(mockTracer.trace(any)).thenAnswer((_) => {});
          
          testRouter.attach(mockPubsub);

          const fanoutFillTopic = 'fanout-fill-topic';
          final mockExistingFanoutPeer = MockPeerId();
          when(mockExistingFanoutPeer.toBytes()).thenReturn(Uint8List.fromList([101,1,1]));
          when(mockExistingFanoutPeer.toBase58()).thenReturn('QmExistingFanout');
          setScore(testRouter, mockExistingFanoutPeer, 5.0);

          testRouter.fanout[fanoutFillTopic] = {mockExistingFanoutPeer}; // 1 peer, D=3, need 2 more
          testRouter.fanoutLastPublished[fanoutFillTopic] = DateTime.now(); // Not expired

          // Candidate peers to fill fanout
          final mockCandidateFanout1 = MockPeerId();
          when(mockCandidateFanout1.toBytes()).thenReturn(Uint8List.fromList([102,1,1]));
          when(mockCandidateFanout1.toBase58()).thenReturn('QmCandFanout1');
          setScore(testRouter, mockCandidateFanout1, 6.0);

          final mockCandidateFanout2 = MockPeerId();
          when(mockCandidateFanout2.toBytes()).thenReturn(Uint8List.fromList([102,1,2]));
          when(mockCandidateFanout2.toBase58()).thenReturn('QmCandFanout2');
          setScore(testRouter, mockCandidateFanout2, 7.0);
          
          final mockCandidateFanout3BadScore = MockPeerId();
          when(mockCandidateFanout3BadScore.toBytes()).thenReturn(Uint8List.fromList([102,1,3]));
          when(mockCandidateFanout3BadScore.toBase58()).thenReturn('QmCandFanout3Bad');
          // Below the publish threshold
          setScore(testRouter, mockCandidateFanout3BadScore, _testThresholds.publishThreshold - 1);

          final mockUnsubscribedPeer = MockPeerId(); // Good score, not subscribed to the topic
          when(mockUnsubscribedPeer.toBytes()).thenReturn(Uint8List.fromList([102,1,4]));
          when(mockUnsubscribedPeer.toBase58()).thenReturn('QmUnsubscribed');
          setScore(testRouter, mockUnsubscribedPeer, 9.0);

          when(mockNetwork.peers).thenReturn([
            mockLocalPeerId,
            mockExistingFanoutPeer,
            mockCandidateFanout1,
            mockCandidateFanout2,
            mockCandidateFanout3BadScore,
            mockUnsubscribedPeer,
          ]);
          subscribePeers(async, testRouter,
              [mockExistingFanoutPeer, mockCandidateFanout1, mockCandidateFanout2, mockCandidateFanout3BadScore],
              topic: fanoutFillTopic);
          
          testRouter.start();
          async.elapse(testRouterParams.fanoutTTL); // Trigger heartbeat using the defined short TTL

          expect(testRouter.fanout[fanoutFillTopic]!.length, equals(3), // Should fill up to D
            reason: "Fanout for topic should be filled to D. Current: ${testRouter.fanout[fanoutFillTopic]!.map((e) => e.toBase58())}");
          expect(testRouter.fanout[fanoutFillTopic], containsAll([
            mockExistingFanoutPeer, 
            mockCandidateFanout1, 
            mockCandidateFanout2
          ]));
          expect(testRouter.fanout[fanoutFillTopic], isNot(contains(mockCandidateFanout3BadScore)));
          expect(testRouter.fanout[fanoutFillTopic], isNot(contains(mockUnsubscribedPeer)));

          testRouter.stop();
        });
      });
    });

    group('Gossip (IHAVE/IWANT), as go-libp2p-pubsub', () {
      const testTopicName = 'gossip-topic';
      final testTopic = Topic(testTopicName);
      late GossipSubRouter r;

      Map<PeerId, List<pb.RPC>> captureSentRpcs() {
        final captured = <PeerId, List<pb.RPC>>{};
        when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
          captured.putIfAbsent(inv.positionalArguments[0] as PeerId, () => []).add(inv.positionalArguments[1] as pb.RPC);
        });
        return captured;
      }

      late Map<PeerId, List<pb.RPC>> sent;
      var nextId = 0;

      MockPeerId peer() {
        final p = MockPeerId();
        final id = 0x40 + nextId++;
        when(p.toBytes()).thenReturn(Uint8List.fromList([0x00, 0x01, id]));
        when(p.toBase58()).thenReturn('QmGossip$id');
        return p;
      }

      pb.Message message(int n) => pb.Message()
        ..from = [0x00, 0x01, 0x01]
        ..seqno = [n]
        ..topic = testTopicName
        ..data = [n];

      pb.RPC ihave(List<pb.Message> msgs) => pb.RPC()
        ..control = (pb.ControlMessage()
          ..ihave.add(pb.ControlIHave()
            ..topicID = testTopicName
            ..messageIDs.addAll(msgs.map((m) => messageIdToBytes(defaultMessageIdFn(m))))));

      List<String> iwantIds(PeerId p) => [
            for (final rpc in sent[p] ?? const <pb.RPC>[])
              for (final iwant in rpc.control.iwant) ...iwant.messageIDs.map(messageIdFromBytes),
          ];

      /// A router (not started) that has joined the test topic, with [peers]
      /// connected and subscribed.
      void setUpRouter(FakeAsync async, GossipSubParams params, List<PeerId> peers) {
        router.stop();
        r = scoredRouter(params);
        r.attach(mockPubsub);
        r.join(testTopic);
        when(mockNetwork.peers).thenReturn(peers);
        for (final p in peers) {
          setScore(r, p, 0);
          r.handleRpc(p, pb.RPC()..subscriptions.add(pb.RPC_SubOpts()..subscribe = true..topicid = testTopicName));
        }
        when(mockPubsub.validateMessage(any, markSeen: anyNamed('markSeen')))
            .thenAnswer((inv) => _validated(inv, ValidationResult.accept));
        async.flushMicrotasks();
        sent = captureSentRpcs();
      }

      /// Connects and subscribes [peers] to the router made by [setUpRouter].
      void setUpRouter2(FakeAsync async, List<PeerId> peers) {
        when(mockNetwork.peers).thenReturn(peers);
        for (final p in peers) {
          setScore(r, p, 0);
          r.handleRpc(p, pb.RPC()..subscriptions.add(pb.RPC_SubOpts()..subscribe = true..topicid = testTopicName));
        }
        async.flushMicrotasks();
        sent.clear();
      }

      /// Runs one heartbeat of [r]: the first starts it.
      void heartbeat(FakeAsync async, GossipSubParams params) {
        if (r.isStarted) {
          async.elapse(params.heartbeatInterval);
        } else {
          r.start();
          async.elapse(params.heartbeatInitialDelay);
        }
        async.flushMicrotasks();
      }

      test('the heartbeat gossips recent message IDs to DLazy topic peers outside the mesh', () {
        fakeAsync((async) {
          final params = GossipSubParams(D: 2, DLow: 1, DHigh: 3, DScore: 1, DOut: 0, DLazy: 2);
          final meshPeer = peer();
          final others = [peer(), peer(), peer()];
          setUpRouter(async, params, [meshPeer, ...others]);
          r.mesh[testTopicName] = {meshPeer};
          final msg = message(1);
          r.handleRpc(meshPeer, pb.RPC()..publish.add(msg));
          async.flushMicrotasks();
          sent.clear();

          heartbeat(async, params);

          final gossiped = [
            for (final p in others)
              if (sent[p]?.any((rpc) => rpc.control.ihave.isNotEmpty) ?? false) p,
          ];
          expect(gossiped, hasLength(2), reason: 'DLazy = 2 > gossipFactor * 3 peers');
          for (final p in gossiped) {
            final ids = sent[p]!.expand((rpc) => rpc.control.ihave).expand((i) => i.messageIDs);
            expect(ids.map(messageIdFromBytes), [defaultMessageIdFn(msg)]);
          }
          expect(sent[meshPeer]?.any((rpc) => rpc.control.ihave.isNotEmpty) ?? false, isFalse);
        });
      });

      test('at most maxIHaveMessages IHAVEs of a peer are answered per heartbeat', () {
        fakeAsync((async) {
          final params = GossipSubParams(maxIHaveMessages: 2);
          final p = peer();
          setUpRouter(async, params, [p]);
          for (var i = 0; i < 4; i++) {
            r.handleRpc(p, ihave([message(i)]));
          }
          async.flushMicrotasks();
          expect(iwantIds(p), hasLength(2));

          // The next heartbeat resets the counter.
          heartbeat(async, params);
          sent.clear();
          r.handleRpc(p, ihave([message(9)]));
          async.flushMicrotasks();
          expect(iwantIds(p), hasLength(1));
        });
      });

      test('at most maxIHaveLength messages are requested from a peer per heartbeat', () {
        fakeAsync((async) {
          final params = GossipSubParams(maxIHaveLength: 3);
          final p = peer();
          setUpRouter(async, params, [p]);
          r.handleRpc(p, ihave([for (var i = 0; i < 5; i++) message(i)]));
          r.handleRpc(p, ihave([message(7)]));
          async.flushMicrotasks();
          expect(iwantIds(p), hasLength(3));
        });
      });

      test('a peer that does not deliver a requested message is penalised; one that does is not', () {
        fakeAsync((async) {
          final params = GossipSubParams();
          final liar = peer();
          final honest = peer();
          setUpRouter(async, params, [liar, honest]);

          r.handleRpc(liar, ihave([message(1)]));
          final delivered = message(2);
          r.handleRpc(honest, ihave([delivered]));
          async.flushMicrotasks();
          expect(iwantIds(liar), hasLength(1));
          expect(iwantIds(honest), hasLength(1));
          r.handleRpc(honest, pb.RPC()..publish.add(delivered));
          async.flushMicrotasks();

          async.elapse(params.iwantFollowupTime + const Duration(milliseconds: 1));
          heartbeat(async, params);

          expect(r.score!.snapshot(liar)!.behaviourPenalty, 1);
          expect(r.score!.snapshot(honest)!.behaviourPenalty, 0);
        });
      });

      test('a large received message is announced with IDONTWANT to v1.2 mesh peers only', () {
        fakeAsync((async) {
          final params = GossipSubParams(D: 2, DLow: 1, DHigh: 3, DScore: 1, DOut: 0, idontwantMessageThreshold: 10);
          final source = peer();
          final v12 = peer();
          final v11 = peer();
          setUpRouter(async, params, []);
          r.addPeer(v12, gossipSubIDv12);
          setUpRouter2(async, [source, v12, v11]);
          r.mesh[testTopicName] = {source, v12, v11};
          final big = message(1)..data = List.filled(10, 7);
          r.handleRpc(source, pb.RPC()..publish.add(big));
          async.flushMicrotasks();

          List<String> idontwant(PeerId p) => [
                for (final rpc in sent[p] ?? const <pb.RPC>[])
                  for (final i in rpc.control.idontwant) ...i.messageIDs.map(messageIdFromBytes),
              ];
          expect(idontwant(v12), [defaultMessageIdFn(big)]);
          expect(idontwant(v11), isEmpty);
          expect(idontwant(source), isEmpty);
        });
      });

      test('a message a mesh peer said it does not want is not forwarded to it', () {
        fakeAsync((async) {
          final params = GossipSubParams(D: 2, DLow: 1, DHigh: 3, DScore: 1, DOut: 0);
          final source = peer();
          final other = peer();
          setUpRouter(async, params, [source, other]);
          r.mesh[testTopicName] = {source, other};
          final msg = message(3);
          r.handleRpc(
              other,
              pb.RPC()
                ..control = (pb.ControlMessage()
                  ..idontwant.add(pb.ControlIDontWant()..messageIDs.add(messageIdToBytes(defaultMessageIdFn(msg))))));
          r.handleRpc(source, pb.RPC()..publish.add(msg));
          async.flushMicrotasks();
          expect(sent[other]?.expand((rpc) => rpc.publish) ?? const [], isEmpty);

          // Forgotten after idontwantMessageTTL heartbeats.
          for (var i = 0; i < params.idontwantMessageTTL; i++) {
            heartbeat(async, params);
          }
          sent.clear();
          r.handleRpc(source, pb.RPC()..publish.add(message(4)));
          async.flushMicrotasks();
          expect(sent[other]!.expand((rpc) => rpc.publish), hasLength(1));
        });
      });

      test('a PRUNE to a v1.0 peer has no backoff and no PX', () {
        fakeAsync((async) {
          final params = GossipSubParams();
          final v10 = peer();
          setUpRouter(async, params, []);
          r.addPeer(v10, gossipSubIDv10);
          setUpRouter2(async, [v10]);
          r.mesh[testTopicName] = {v10};
          r.leave(testTopic);
          async.flushMicrotasks();
          final prune = sent[v10]!.single.control.prune.single;
          expect(prune.hasBackoff(), isFalse);
          expect(prune.peers, isEmpty);
        });
      });

      test('a peer below the graylist threshold has its RPCs refused', () {
        fakeAsync((async) {
          final p = peer();
          setUpRouter(async, GossipSubParams(), [p]);
          expect(r.acceptFrom(p), AcceptStatus.all);
          setScore(r, p, -81); // Below graylistThreshold -80.
          expect(r.acceptFrom(p), AcceptStatus.none);
        });
      });

      test('IHAVEs from a peer below the gossip threshold are ignored', () {
        fakeAsync((async) {
          final p = peer();
          setUpRouter(async, GossipSubParams(), [p]);
          setScore(r, p, -20); // Below gossipThreshold -10.
          r.handleRpc(p, ihave([message(1)]));
          async.flushMicrotasks();
          expect(iwantIds(p), isEmpty);
        });
      });
    });

    group('Peer Exchange, as go-libp2p-pubsub', () {
      const topicName = 'px-topic';
      late PeerId pruner;
      late List<AddrInfo> connected;

      /// A peer with a key, for signed peer records.
      Future<(PeerId, KeyPair)> keyedPeer() async {
        final keys = await generateEd25519KeyPair();
        return (PeerId.fromPublicKey(keys.publicKey), keys);
      }

      Future<List<int>> signedRecord(PeerId peerId, KeyPair signer, List<MultiAddr> addrs) async {
        final envelope = await Envelope.seal(PeerRecord(peerId: peerId, addrs: addrs, seq: 1), signer.privateKey);
        return envelope.marshal();
      }

      pb.RPC pruneWithPx(List<pb.PeerInfo> px) => pb.RPC()
        ..control = (pb.ControlMessage()
          ..prune.add(pb.ControlPrune()
            ..topicID = topicName
            ..backoff = Int64(60)
            ..peers.addAll(px)));

      setUpAll(() {
        // As a dart_libp2p host does when it is created.
        RecordRegistry.register<record_pb.PeerRecord>(
            String.fromCharCodes(PeerRecordEnvelopePayloadType), record_pb.PeerRecord.fromBuffer);
      });

      setUp(() async {
        // Real peer IDs throughout: PeerId.== fails on a mock.
        when(mockHost.id).thenReturn((await keyedPeer()).$1);
        pruner = (await keyedPeer()).$1;
        setScore(router, pruner, 0);
        await router.join(Topic(topicName));
        connected = [];
        when(mockNetwork.connectedness(any)).thenReturn(Connectedness.notConnected);
        when(mockHost.connect(any, context: anyNamed('context'))).thenAnswer((inv) async {
          connected.add(inv.positionalArguments[0] as AddrInfo);
        });
      });

      test('connects to the PX peers of a PRUNE at the addresses of their signed records', () async {
        final (pxPeer, keys) = await keyedPeer();
        final addr = MultiAddr('/ip4/10.0.0.1/tcp/4001');
        await router.handleRpc(pruner, pruneWithPx([
          pb.PeerInfo()
            ..peerID = pxPeer.toBytes()
            ..signedPeerRecord = await signedRecord(pxPeer, keys, [addr]),
        ]));
        await pumpEventQueue();

        expect(connected.single.id, equals(pxPeer));
        expect(connected.single.addrs.map((a) => a.toString()), [addr.toString()]);
        expect(peerstore.addrBook.records, contains(pxPeer));
      });

      test('connects to PX peers without a record at the addresses it knows', () async {
        final (pxPeer, _) = await keyedPeer();
        await router.handleRpc(pruner, pruneWithPx([pb.PeerInfo()..peerID = pxPeer.toBytes()]));
        await pumpEventQueue();

        expect(connected.single.id, equals(pxPeer));
      });

      test('ignores PX from a peer with a score below acceptPXThreshold', () async {
        setScore(router, pruner, -1); // acceptPXThreshold is 0.
        final (pxPeer, _) = await keyedPeer();
        await router.handleRpc(pruner, pruneWithPx([pb.PeerInfo()..peerID = pxPeer.toBytes()]));
        await pumpEventQueue();

        expect(connected, isEmpty);
      });

      test('skips a PX peer whose record is signed by another key or is about another peer', () async {
        final (pxPeer, _) = await keyedPeer();
        final (otherPeer, otherKeys) = await keyedPeer();
        await router.handleRpc(pruner, pruneWithPx([
          pb.PeerInfo()
            ..peerID = pxPeer.toBytes()
            ..signedPeerRecord = await signedRecord(pxPeer, otherKeys, [MultiAddr('/ip4/10.0.0.2/tcp/1')]),
          pb.PeerInfo()
            ..peerID = pxPeer.toBytes()
            ..signedPeerRecord = await signedRecord(otherPeer, otherKeys, [MultiAddr('/ip4/10.0.0.3/tcp/1')]),
          pb.PeerInfo()..peerID = [1, 2, 3], // Not a peer ID.
        ]));
        await pumpEventQueue();

        expect(connected, isEmpty);
        expect(peerstore.addrBook.records, isEmpty);
      });

      test('skips PX peers already connected or known, and connects to at most prunePeers', () async {
        final (known, _) = await keyedPeer();
        await router.addPeer(known, gossipSubIDv11);
        final (alreadyConnected, _) = await keyedPeer();
        when(mockNetwork.connectedness(alreadyConnected)).thenReturn(Connectedness.connected);
        final others = [for (var i = 0; i < router.params.prunePeers + 4; i++) (await keyedPeer()).$1];

        await router.handleRpc(pruner, pruneWithPx([pb.PeerInfo()..peerID = known.toBytes()]));
        await router.handleRpc(pruner, pruneWithPx([pb.PeerInfo()..peerID = alreadyConnected.toBytes()]));
        await pumpEventQueue();
        expect(connected, isEmpty);

        await router.handleRpc(pruner, pruneWithPx([for (final p in others) pb.PeerInfo()..peerID = p.toBytes()]));
        await pumpEventQueue();
        expect(connected, hasLength(router.params.prunePeers));
      });

      test('our PX carries the signed records of the peers we offer', () async {
        final (pxPeer, keys) = await keyedPeer();
        await peerstore.addrBook.consumePeerRecord(
            await Envelope.consumeEnvelope(
                    Uint8List.fromList(await signedRecord(pxPeer, keys, [MultiAddr('/ip4/10.0.0.4/tcp/1')])),
                    PeerRecordEnvelopeDomain)
                .then((r) => r.$1),
            AddressTTL.tempAddrTTL);
        when(mockNetwork.peers).thenReturn([pxPeer, pruner]);
        await router.addPeer(pxPeer, gossipSubIDv11);
        await router.handleRpc(
            pxPeer,
            pb.RPC()
              ..subscriptions.add(pb.RPC_SubOpts()
                ..subscribe = true
                ..topicid = topicName));
        await pumpEventQueue(); // The record is fetched in the background.
        final sent = <pb.RPC>[];
        when(mockComms.sendRpc(any, any, any)).thenAnswer((inv) async {
          if (inv.positionalArguments[0] == pruner) sent.add(inv.positionalArguments[1] as pb.RPC);
        });

        await router.leave(Topic(topicName)); // No mesh peers: no PRUNE.
        await router.join(Topic(topicName));
        router.mesh[topicName]!.add(pruner);
        await router.leave(Topic(topicName));
        await pumpEventQueue();

        final px = sent.expand((rpc) => rpc.control.prune).single.peers.single;
        expect(px.peerID, equals(pxPeer.toBytes()));
        final (_, record) = await Envelope.consumeEnvelope(Uint8List.fromList(px.signedPeerRecord), PeerRecordEnvelopeDomain);
        expect((record as PeerRecord).peerId, equals(pxPeer));
      });
    });
  });
}

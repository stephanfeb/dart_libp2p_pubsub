import 'dart:typed_data';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/score.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/score_params.dart';
import 'package:test/test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:clock/clock.dart' as clk; // Use an alias to avoid conflict if 'clock' is used elsewhere

void main() {
  group('PeerScore', () {
    // No group-level PeerScore instance. Each test will create its own.
    late PeerScoreParams params;
    late PeerId peerId; // Can be used by tests to create their PeerScore instances

    setUp(() async { // Make setUp asynchronous
      params = PeerScoreParams.defaultParams;
      peerId = await PeerId.random(); // Await the Future
    });

    test('initial score is zero', () {
      final localPeerScore = PeerScore(peerId, params); // Create local instance
      expect(localPeerScore.score, 0);
      expect(localPeerScore.topicStats, isEmpty);
      expect(localPeerScore.knownIPs, isEmpty);
      expect(localPeerScore.ipColocated, isFalse);
      expect(localPeerScore.behaviourPenalty, 0);
      expect(localPeerScore.appSpecificScoreValue, 0);
      expect(localPeerScore.graylistUntil, isNull);
    });

    test('recordGraft and recordPrune update mesh status and graftTime', () {
      final localPeerScore = PeerScore(peerId, params);
      const topic = 'test_topic';
      localPeerScore.recordGraft(topic);
      expect(localPeerScore.topicStats[topic]?.inMesh, isTrue);
      expect(localPeerScore.topicStats[topic]?.graftTime, isNotNull);
      final graftTime = localPeerScore.topicStats[topic]?.graftTime;

      localPeerScore.recordPrune(topic);
      expect(localPeerScore.topicStats[topic]?.inMesh, isFalse);
      expect(localPeerScore.topicStats[topic]?.graftTime, isNull);
      expect(localPeerScore.topicStats[topic]?.meshTime, greaterThan(Duration.zero));

      localPeerScore.recordGraft(topic);
      expect(localPeerScore.topicStats[topic]?.inMesh, isTrue);
      expect(localPeerScore.topicStats[topic]?.graftTime, isNot(equals(graftTime)));
    });

    test('recordFirstMessageDelivery updates counters and lastSuccessfulDelivery', () {
      final localPeerScore = PeerScore(peerId, params);
      const topic = 'test_topic';
      localPeerScore.recordFirstMessageDelivery(topic);
      expect(localPeerScore.topicStats[topic]?.firstMessageDeliveries, 1);
      expect(localPeerScore.topicStats[topic]?.lastSuccessfulDelivery, isNotNull);
      final firstDeliveryTime = localPeerScore.topicStats[topic]?.lastSuccessfulDelivery;

      localPeerScore.recordFirstMessageDelivery(topic);
      expect(localPeerScore.topicStats[topic]?.firstMessageDeliveries, 2);
      expect(localPeerScore.topicStats[topic]?.lastSuccessfulDelivery, isNot(equals(firstDeliveryTime)));
    });

    test('recordMeshMessageDelivery updates counters and activates mesh deliveries', () {
      final localPeerScore = PeerScore(peerId, params);
      const topic = 'test_topic';
      localPeerScore.recordGraft(topic);
      localPeerScore.recordMeshMessageDelivery(topic);

      expect(localPeerScore.topicStats[topic]?.meshMessageDeliveries, 1);
      expect(localPeerScore.topicStats[topic]?.meshMessageDeliveriesActive, isTrue);
      expect(localPeerScore.topicStats[topic]?.meshMessageDeliveriesActivation, isNotNull);
      expect(localPeerScore.topicStats[topic]?.lastSuccessfulDelivery, isNotNull);
      final firstDeliveryTime = localPeerScore.topicStats[topic]?.lastSuccessfulDelivery;

      localPeerScore.recordMeshMessageDelivery(topic);
      expect(localPeerScore.topicStats[topic]?.meshMessageDeliveries, 2);
      expect(localPeerScore.topicStats[topic]?.lastSuccessfulDelivery, isNot(equals(firstDeliveryTime)));

      localPeerScore.recordPrune(topic);
      localPeerScore.recordMeshMessageDelivery(topic);
      expect(localPeerScore.topicStats[topic]?.meshMessageDeliveries, 2); 
    });

    test('recordInvalidMessage increments topic and global counters', () {
      final localPeerScore = PeerScore(peerId, params);
      const topic = 'test_topic';
      localPeerScore.recordInvalidMessage(topic);
      expect(localPeerScore.topicStats[topic]?.invalidMessageDeliveries, 1);
      expect(localPeerScore.invalidMessageDeliveries, 1);

      localPeerScore.recordInvalidMessage(topic);
      expect(localPeerScore.topicStats[topic]?.invalidMessageDeliveries, 2);
      expect(localPeerScore.invalidMessageDeliveries, 2);
    });

    test('recordMeshMessageFailure increments penalty counter', () {
      final localPeerScore = PeerScore(peerId, params);
      const topic = 'test_topic';
      localPeerScore.recordGraft(topic);
      localPeerScore.recordMeshMessageFailure(topic);
      expect(localPeerScore.topicStats[topic]?.meshFailurePenalty, 1);

      localPeerScore.recordMeshMessageFailure(topic);
      expect(localPeerScore.topicStats[topic]?.meshFailurePenalty, 2);

      localPeerScore.recordPrune(topic);
      localPeerScore.recordMeshMessageFailure(topic);
      expect(localPeerScore.topicStats[topic]?.meshFailurePenalty, 2);
    });

    test('addPenalty and resetPenalty manage behavioral penalty', () {
      final localPeerScore = PeerScore(peerId, params);
      localPeerScore.addPenalty(5);
      expect(localPeerScore.behaviourPenalty, 5);
      localPeerScore.addPenalty(10);
      expect(localPeerScore.behaviourPenalty, 15);
      localPeerScore.resetPenalty();
      expect(localPeerScore.behaviourPenalty, 0);
    });

    test('score decays over time', () async {
      // This test uses fakeAsync, so it creates its own PeerId and passes the clock.
      final localTestPeerId = await PeerId.random();
      fakeAsync((fa) { // Changed 'async' to 'fa' for clarity
        final testParams = PeerScoreParams(
          appSpecificScore: (_) => 100.0,
          scoreDecay: 0.9, 
          decayInterval: Duration(seconds: 1),
          decayToZero: 0.01,
        );
        final localPeerScore = PeerScore(localTestPeerId, testParams, clock: clk.clock); 
        
        localPeerScore.refreshScore(); 
        expect(localPeerScore.score, closeTo(100.0, 0.001));

        fa.elapse(Duration(seconds: 1));
        localPeerScore.refreshScore(); 
        expect(localPeerScore.score, closeTo(190.0, 0.001));

        fa.elapse(Duration(seconds: 1));
        localPeerScore.refreshScore(); 
        expect(localPeerScore.score, closeTo(271.0, 0.001));
        
        localPeerScore.score = 0.05; 
        fa.elapse(Duration(seconds: 1)); 
        localPeerScore.refreshScore(); 
        expect(localPeerScore.score, closeTo(100.045, 0.0001));
        
        localPeerScore.score = 0.005; 
        fa.elapse(Duration(seconds: 1)); 
        localPeerScore.refreshScore(); 
        expect(localPeerScore.score, closeTo(100.0, 0.0001));
      });
    });

    test('peer is graylisted when score drops below threshold', () async {
      final localTestPeerId = await PeerId.random();
      fakeAsync((fa) {
        final graylistParams = PeerScoreParams(
          graylistThreshold: -50.0,
          graylistDuration: Duration(minutes: 1),
          decayInterval: Duration(seconds: 1), 
        );
        // Pass the fake clock to PeerScore
        final localPeerScore = PeerScore(localTestPeerId, graylistParams, clock: clk.clock);

        expect(localPeerScore.graylistUntil, isNull);

        localPeerScore.score = -60.0;
        localPeerScore.refreshScore(); 
        
        expect(localPeerScore.graylistUntil, isNotNull);
        final graylistEndTime = localPeerScore.graylistUntil!;
        final expectedEndTime = localPeerScore.lastUpdated.add(graylistParams.graylistDuration);
        expect(graylistEndTime.millisecondsSinceEpoch, expectedEndTime.millisecondsSinceEpoch);

        localPeerScore.score = -40.0;
        fa.elapse(Duration(seconds:1)); 
        localPeerScore.refreshScore();
        expect(localPeerScore.graylistUntil, isNull);
      });
    });
    
    test('IP colocation factor applies penalty', () async { 
      final testPeerId = await PeerId.random(); 

      fakeAsync((fa) { // Changed 'async' to 'fa'
        final colocParams = PeerScoreParams(
          ipColocationFactor: 0.5, 
          ipColocationFactorThreshold: 1, 
          decayInterval: Duration(seconds: 1),
          defaultTopicParams: TopicScoreParams(
            topicWeight: 10, 
            timeInMeshQuantum: Duration(seconds: 1),
            timeInMeshCap: 100,
            topicWeightCapGracePeriod: Duration(days: 365), 
          )
        );
        
        const topic = 'coloc_topic';

        PeerScore currentPeerScore = PeerScore(testPeerId, colocParams, clock: clk.clock);
        currentPeerScore.recordGraft(topic);
        fa.elapse(Duration(seconds: 1)); 
        currentPeerScore.refreshScore(); 
        expect(currentPeerScore.score, closeTo(10.0, 0.001), reason: "Score without colocation should be 10.0");

        currentPeerScore = PeerScore(testPeerId, colocParams, clock: clk.clock); 
        currentPeerScore.recordGraft(topic);
        currentPeerScore.setIPColocated(true); 
        fa.elapse(Duration(seconds: 1)); 
        currentPeerScore.refreshScore(); 
        expect(currentPeerScore.score, closeTo(5.0, 0.001), reason: "Score with colocation should be 5.0");
        
        final negativeScoreTestParams = PeerScoreParams(
          ipColocationFactor: 0.5,
          ipColocationFactorThreshold: 1,
          decayInterval: Duration(seconds: 1),
          defaultTopicParams: TopicScoreParams(
            topicWeight: 10, 
            timeInMeshQuantum: Duration(seconds: 1),
            timeInMeshCap: 100,
            meshFailurePenaltyWeight: -30, 
            topicWeightCapGracePeriod: Duration(days: 365),
          )
        );
        currentPeerScore = PeerScore(testPeerId, negativeScoreTestParams, clock: clk.clock);
        currentPeerScore.recordGraft(topic);
        currentPeerScore.recordMeshMessageFailure(topic); 
        currentPeerScore.setIPColocated(true);
        fa.elapse(Duration(seconds: 1)); 
        
        currentPeerScore.refreshScore(); 
        expect(currentPeerScore.score, closeTo(-20.0, 0.001), reason: "Score with negative topic sum and colocation should be -20.0");
      });
    });

    // TODO: Add tests for P1 cap grace period
    // TODO: Add tests for P2 (mesh message deliveries) activation window and decay
    // TODO: Add tests for P3a (first message deliveries) decay
    // TODO: Add tests for P6 (behavioural penalty) decay and cap
    // TODO: Add tests for scoreMin/scoreMax caps
    // TODO: Test TopicScoreParams overrides
  });

  group('TopicScoreStats', () {
    test('resetCounters resets relevant fields', () {
      final stats = TopicScoreStats();
      stats.firstMessageDeliveries = 5;
      stats.meshMessageDeliveries = 10;
      stats.meshMessageDeliveriesActive = true; // This is not reset by resetCounters
      stats.meshFailurePenalty = 2;
      stats.invalidMessageDeliveries = 1;
      stats.inMesh = true; // Not reset
      stats.graftTime = DateTime.now(); // Not reset
      stats.meshTime = Duration(seconds: 10); // Not reset

      stats.resetCounters();

      expect(stats.firstMessageDeliveries, 0);
      expect(stats.meshMessageDeliveries, 0);
      expect(stats.meshMessageDeliveriesActive, isTrue); // Remains true
      expect(stats.meshFailurePenalty, 0);
      expect(stats.invalidMessageDeliveries, 0);
      expect(stats.inMesh, isTrue);
      expect(stats.graftTime, isNotNull);
      expect(stats.meshTime, Duration(seconds: 10));
    });
  });

  group('ScoreParams', () {
    test('default params are created successfully', () {
      final defaultParams = PeerScoreParams.defaultParams;
      expect(defaultParams, isA<PeerScoreParams>());
      // Optionally, check some default values if they are critical
      expect(defaultParams.graylistThreshold, isNotNull);
    });

    // Add more tests for ScoreParams validation and specific parameter settings
  });
}

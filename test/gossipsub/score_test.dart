import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/score.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/score_params.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const topic = 'scored-topic';

final peerA = PeerId.fromString('12D3KooWNVJVohNejPeDRpVTKXDhYd2BuKstxAwDHMMdg22uZaye');
final peerB = PeerId.fromString('12D3KooWQzSY5S6Tnk2A3LnJnNGeyC4k9PVCzK6a3BGzSzVvG8n3');
final peerC = PeerId.fromString('12D3KooWLy6yLRMoDpvinNhPkTLmsfd3MiUiALkUt6A2kiMgxyib');

PeerScore scorer(TopicScoreParams topicParams,
        {double topicScoreCap = 0,
        double behaviourPenaltyWeight = 0,
        double behaviourPenaltyThreshold = 0,
        double ipColocationFactorWeight = 0,
        int ipColocationFactorThreshold = 1,
        List<String> whitelist = const [],
        Map<PeerId, List<String>> ips = const {},
        double Function(PeerId)? appScore,
        double appWeight = 0}) =>
    PeerScore(
      PeerScoreParams(
        topics: {topic: topicParams},
        topicScoreCap: topicScoreCap,
        appSpecificScore: appScore ?? (_) => 0,
        appSpecificWeight: appWeight,
        behaviourPenaltyWeight: behaviourPenaltyWeight,
        behaviourPenaltyThreshold: behaviourPenaltyThreshold,
        behaviourPenaltyDecay: 0.9,
        ipColocationFactorWeight: ipColocationFactorWeight,
        ipColocationFactorThreshold: ipColocationFactorThreshold,
        ipColocationFactorWhitelist: whitelist,
      ),
      connectionIps: (p) => ips[p] ?? const [],
    );

void main() {
  group('PeerScore, as go-libp2p-pubsub score_test.go', () {
    test('an unknown peer scores 0', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1));
      expect(s.score(peerA), 0);
    });

    test('P1: time in mesh, in quanta, capped', () {
      fakeAsync((async) {
        final s = scorer(const TopicScoreParams(
          topicWeight: 0.5,
          timeInMeshWeight: 1,
          timeInMeshQuantum: Duration(milliseconds: 1),
          timeInMeshCap: 3600,
        ));
        s.addPeer(peerA);
        s.graft(peerA, topic);
        async.elapse(const Duration(milliseconds: 200));
        s.refreshScores();
        // 200 quanta * weight 1 * topic weight 0.5.
        expect(s.score(peerA), closeTo(100, 1));

        async.elapse(const Duration(seconds: 10));
        s.refreshScores();
        expect(s.score(peerA), 3600 * 0.5); // Capped.
      });
    });

    test('P2: first message deliveries, capped, decaying', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        firstMessageDeliveriesWeight: 1,
        firstMessageDeliveriesDecay: 0.5,
        firstMessageDeliveriesCap: 3,
      ));
      s.addPeer(peerA);
      for (var i = 0; i < 5; i++) {
        s.validateMessage('m$i');
        s.deliverMessage('m$i', peerA, topic);
      }
      expect(s.score(peerA), 3); // Capped.
      s.refreshScores();
      expect(s.score(peerA), 1.5);
    });

    test('P3: mesh delivery deficit squared, once active', () {
      fakeAsync((async) {
        final s = scorer(const TopicScoreParams(
          topicWeight: 1,
          meshMessageDeliveriesWeight: -1,
          meshMessageDeliveriesDecay: 0.99,
          meshMessageDeliveriesCap: 100,
          meshMessageDeliveriesThreshold: 20,
          meshMessageDeliveriesWindow: Duration(milliseconds: 10),
          meshMessageDeliveriesActivation: Duration(seconds: 1),
        ));
        for (final p in [peerA, peerB, peerC]) {
          s.addPeer(p);
          s.graft(p, topic);
        }
        // Not active yet: no penalty.
        s.refreshScores();
        expect(s.score(peerA), 0);

        // A delivers first; B forwards within the window; C late.
        for (var i = 0; i < 10; i++) {
          final id = 'm$i';
          s.validateMessage(id);
          s.deliverMessage(id, peerA, topic);
          s.duplicateMessage(id, peerB, topic);
        }
        async.elapse(const Duration(milliseconds: 20));
        for (var i = 0; i < 10; i++) {
          s.duplicateMessage('m$i', peerC, topic);
        }
        async.elapse(const Duration(seconds: 1));
        s.refreshScores();

        // A and B: 10 deliveries (decayed once to 9.9), deficit 10.1.
        expect(s.score(peerA), closeTo(-10.1 * 10.1, 1e-9));
        expect(s.score(peerB), closeTo(-10.1 * 10.1, 1e-9));
        // C: no timely delivery, deficit 20.
        expect(s.score(peerC), -400);
      });
    });

    test('P3b: a pruned peer with a deficit keeps a sticky penalty', () {
      fakeAsync((async) {
        // As Go's TestScoreMeshFailurePenalty, P3 has weight 0 so that P3b
        // shows alone.
        final s = scorer(const TopicScoreParams(
          topicWeight: 1,
          meshMessageDeliveriesWeight: 0,
          meshMessageDeliveriesDecay: 0.5,
          meshMessageDeliveriesCap: 10,
          meshMessageDeliveriesThreshold: 3,
          meshMessageDeliveriesActivation: Duration(seconds: 1),
          meshFailurePenaltyWeight: -1,
          meshFailurePenaltyDecay: 0.5,
        ));
        s.addPeer(peerA);
        s.graft(peerA, topic);
        async.elapse(const Duration(seconds: 2));
        s.refreshScores();
        expect(s.score(peerA), 0);
        s.prune(peerA, topic);
        expect(s.score(peerA), -9); // Deficit 3, squared: sticky.
        s.refreshScores();
        expect(s.score(peerA), -4.5); // Decays.
      });
    });

    test('P4: invalid messages squared, and copies of an invalid message', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -1,
        invalidMessageDeliveriesDecay: 0.5,
      ));
      s.addPeer(peerA);
      s.addPeer(peerB);
      s.addPeer(peerC);

      // B forwards the message while it is in validation; C after.
      s.validateMessage('bad');
      s.duplicateMessage('bad', peerB, topic);
      s.rejectMessage('bad', peerA, topic, RejectReason.validationFailed);
      s.duplicateMessage('bad', peerC, topic);
      for (final p in [peerA, peerB, peerC]) {
        expect(s.score(p), -1, reason: '$p');
      }

      s.validateMessage('bad2');
      s.rejectMessage('bad2', peerA, topic, RejectReason.validationFailed);
      expect(s.score(peerA), -4);
      s.refreshScores();
      expect(s.score(peerA), -1);
    });

    test('ignored and throttled messages are not penalised, nor their copies', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -1,
        invalidMessageDeliveriesDecay: 0.5,
      ));
      s.addPeer(peerA);
      s.addPeer(peerB);
      for (final reason in [RejectReason.validationIgnored, RejectReason.validationThrottled]) {
        final id = 'msg-$reason';
        s.validateMessage(id);
        s.rejectMessage(id, peerA, topic, reason);
        s.duplicateMessage(id, peerB, topic);
      }
      expect(s.score(peerA), 0);
      expect(s.score(peerB), 0);
    });

    test('a bad signature penalises the sender only and is not tracked', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -1,
        invalidMessageDeliveriesDecay: 0.5,
      ));
      s.addPeer(peerA);
      s.addPeer(peerB);
      s.rejectMessage('forged', peerA, topic, RejectReason.invalidSignature);
      // The genuine message with the same ID is valid.
      s.validateMessage('forged');
      s.deliverMessage('forged', peerB, topic);
      s.duplicateMessage('forged', peerB, topic);
      expect(s.score(peerA), -1);
      expect(s.score(peerB), 0);
    });

    test('topics not in params are not scored', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -1,
        invalidMessageDeliveriesDecay: 0.5,
      ));
      s.addPeer(peerA);
      s.rejectMessage('x', peerA, 'other-topic', RejectReason.invalidSignature);
      expect(s.score(peerA), 0);
    });

    test('topic score cap applies to the topic part only', () {
      final s = scorer(
        const TopicScoreParams(
          topicWeight: 1,
          firstMessageDeliveriesWeight: 10,
          firstMessageDeliveriesDecay: 0.5,
          firstMessageDeliveriesCap: 100,
        ),
        topicScoreCap: 15,
        appScore: (_) => 1,
        appWeight: 2,
      );
      s.addPeer(peerA);
      for (var i = 0; i < 5; i++) {
        s.deliverMessage('m$i', peerA, topic);
      }
      expect(s.score(peerA), 15 + 2);
    });

    test('P6: IP colocation, squared surplus over the threshold, whitelist', () {
      final ips = {
        peerA: ['1.2.3.4'],
        peerB: ['1.2.3.4'],
        peerC: ['1.2.3.4'],
      };
      final s = scorer(const TopicScoreParams(topicWeight: 1),
          ipColocationFactorWeight: -1, ipColocationFactorThreshold: 1, ips: ips);
      for (final p in [peerA, peerB, peerC]) {
        s.addPeer(p);
      }
      // 3 peers, threshold 1: surplus 2, squared.
      expect(s.score(peerA), -4);

      final w = scorer(const TopicScoreParams(topicWeight: 1),
          ipColocationFactorWeight: -1,
          ipColocationFactorThreshold: 1,
          whitelist: ['1.2.0.0/16'],
          ips: ips);
      for (final p in [peerA, peerB, peerC]) {
        w.addPeer(p);
      }
      expect(w.score(peerA), 0);
    });

    test('P6: an IPv6 peer also counts for its /64', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1),
          ipColocationFactorWeight: -1,
          ipColocationFactorThreshold: 1,
          ips: {
            peerA: ['2001:db8::1'],
            peerB: ['2001:db8::2'],
          });
      s.addPeer(peerA);
      s.addPeer(peerB);
      expect(s.score(peerA), -1); // 2 peers in 2001:db8::/64.
    });

    test('P7: behaviour penalty squared above the threshold, decaying', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1),
          behaviourPenaltyWeight: -1, behaviourPenaltyThreshold: 1);
      s.addPeer(peerA);
      s.addPenalty(peerA, 1);
      expect(s.score(peerA), 0); // At the threshold.
      s.addPenalty(peerA, 2);
      expect(s.score(peerA), -4); // (3 - 1)^2.
      s.refreshScores();
      expect(s.score(peerA), closeTo(-(2.7 - 1) * (2.7 - 1), 1e-9));
    });

    test('a single penalty decays to zero rather than sticking', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1), behaviourPenaltyWeight: -10);
      s.addPeer(peerA);
      s.addPenalty(peerA, 1);
      expect(s.score(peerA), -10);
      for (var i = 0; i < 60; i++) {
        s.refreshScores();
      }
      expect(s.score(peerA), 0);
    });

    test('retainScore: a negative score is kept, a positive one is not', () {
      fakeAsync((async) {
        final s = PeerScore(
          const PeerScoreParams(
            behaviourPenaltyWeight: -1,
            behaviourPenaltyDecay: 0.9,
            appSpecificWeight: 1,
            retainScore: Duration(minutes: 10),
          ).copyWithAppScore((p) => p == peerB ? 5 : 0),
        );
        s.addPeer(peerA);
        s.addPeer(peerB);
        s.addPenalty(peerA, 2);

        s.removePeer(peerA);
        s.removePeer(peerB);
        expect(s.snapshot(peerB), isNull); // Positive: deleted.
        expect(s.score(peerA), -4);

        // Retained scores do not decay; reconnecting keeps them.
        async.elapse(const Duration(minutes: 5));
        s.refreshScores();
        expect(s.score(peerA), -4);
        s.addPeer(peerA);
        expect(s.score(peerA), -4);

        s.removePeer(peerA);
        async.elapse(const Duration(minutes: 11));
        s.refreshScores();
        expect(s.snapshot(peerA), isNull);
      });
    });

    test('mesh failure penalty is applied when a retained peer leaves the mesh', () {
      fakeAsync((async) {
        final s = scorer(const TopicScoreParams(
          topicWeight: 1,
          meshMessageDeliveriesWeight: -1,
          meshMessageDeliveriesDecay: 0.5,
          meshMessageDeliveriesCap: 10,
          meshMessageDeliveriesThreshold: 2,
          meshMessageDeliveriesActivation: Duration(seconds: 1),
          meshFailurePenaltyWeight: -1,
          meshFailurePenaltyDecay: 0.5,
        ));
        s.addPeer(peerA);
        s.graft(peerA, topic);
        async.elapse(const Duration(seconds: 2));
        s.refreshScores();
        s.removePeer(peerA);
        final stats = s.snapshot(peerA)!.topics[topic]!;
        expect(stats.inMesh, isFalse);
        expect(stats.meshFailurePenalty, 4);
      });
    });
  });

  group('score parameter validation, as go-libp2p-pubsub', () {
    test('valid defaults', () {
      const PeerScoreParams().validate();
      const PeerScoreThresholds().validate();
      const TopicScoreParams(topicWeight: 1).validate();
    });

    test('invalid parameters are refused', () {
      for (final params in [
        const PeerScoreParams(topicScoreCap: -1),
        const PeerScoreParams(ipColocationFactorWeight: 1),
        const PeerScoreParams(ipColocationFactorWeight: -1, ipColocationFactorThreshold: 0),
        const PeerScoreParams(ipColocationFactorWhitelist: ['not-a-cidr']),
        const PeerScoreParams(behaviourPenaltyWeight: 1),
        const PeerScoreParams(behaviourPenaltyWeight: -1, behaviourPenaltyDecay: 1),
        const PeerScoreParams(decayInterval: Duration(milliseconds: 500)),
        const PeerScoreParams(decayToZero: 0),
        const PeerScoreParams(topics: {topic: TopicScoreParams(topicWeight: -1)}),
        const PeerScoreParams(topics: {topic: TopicScoreParams(timeInMeshWeight: 1)}), // No cap.
        const PeerScoreParams(topics: {topic: TopicScoreParams(meshMessageDeliveriesWeight: 1)}),
        const PeerScoreParams(topics: {topic: TopicScoreParams(invalidMessageDeliveriesWeight: 1)}),
        const PeerScoreParams(topics: {topic: TopicScoreParams(invalidMessageDeliveriesDecay: 1)}),
      ]) {
        expect(params.validate, throwsArgumentError);
      }
    });

    test('inconsistent thresholds are refused', () {
      for (final t in [
        const PeerScoreThresholds(gossipThreshold: 1),
        const PeerScoreThresholds(gossipThreshold: -10, publishThreshold: -5),
        const PeerScoreThresholds(publishThreshold: -10, gossipThreshold: -5, graylistThreshold: -5),
        const PeerScoreThresholds(acceptPXThreshold: -1),
        const PeerScoreThresholds(opportunisticGraftThreshold: -1),
      ]) {
        expect(t.validate, throwsArgumentError);
      }
    });

    test('scoreParameterDecay matches Go', () {
      // ScoreParameterDecay(time.Hour) in Go is 0.01^(1/3600).
      expect(scoreParameterDecay(const Duration(hours: 1)), closeTo(0.998721, 1e-6));
    });
  });


  group('setTopicScoreParams, as go-libp2p-pubsub Topic.SetScoreParams', () {
    test('a topic added after the scorer is scored from then on', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1));
      s.addPeer(peerA);
      s.validateMessage('m1');
      s.rejectMessage('m1', peerA, 'late-topic', RejectReason.validationFailed);
      expect(s.score(peerA), 0, reason: 'late-topic not scored yet');

      s.setTopicScoreParams('late-topic', const TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -1,
        invalidMessageDeliveriesDecay: 0.5,
      ));
      expect(s.topicScoreParams('late-topic')?.invalidMessageDeliveriesWeight, -1);
      s.validateMessage('m2');
      s.rejectMessage('m2', peerA, 'late-topic', RejectReason.validationFailed);
      expect(s.score(peerA), -1);
    });

    test('lowering the delivery caps caps the counters', () {
      final s = scorer(const TopicScoreParams(
        topicWeight: 1,
        firstMessageDeliveriesWeight: 1,
        firstMessageDeliveriesDecay: 0.5,
        firstMessageDeliveriesCap: 100,
      ));
      s.addPeer(peerA);
      for (var i = 0; i < 10; i++) {
        s.validateMessage('m$i');
        s.deliverMessage('m$i', peerA, topic);
      }
      expect(s.snapshot(peerA)!.topics[topic]!.firstMessageDeliveries, 10);
      s.setTopicScoreParams(topic, const TopicScoreParams(
        topicWeight: 1,
        firstMessageDeliveriesWeight: 1,
        firstMessageDeliveriesDecay: 0.5,
        firstMessageDeliveriesCap: 4,
      ));
      expect(s.snapshot(peerA)!.topics[topic]!.firstMessageDeliveries, 4);
      expect(s.score(peerA), 4);
    });

    test('invalid parameters are refused', () {
      final s = scorer(const TopicScoreParams(topicWeight: 1));
      expect(() => s.setTopicScoreParams(topic, const TopicScoreParams(topicWeight: -1)), throwsArgumentError);
    });
  });
}

extension on PeerScoreParams {
  PeerScoreParams copyWithAppScore(double Function(PeerId) appScore) => PeerScoreParams(
        topics: topics,
        appSpecificScore: appScore,
        appSpecificWeight: appSpecificWeight,
        behaviourPenaltyWeight: behaviourPenaltyWeight,
        behaviourPenaltyDecay: behaviourPenaltyDecay,
        retainScore: retainScore,
      );
}

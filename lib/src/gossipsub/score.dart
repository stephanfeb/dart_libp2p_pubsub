import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:clock/clock.dart';
import 'score_params.dart'; // Import the actual PeerScoreParams

/// Holds scoring statistics for a peer within a specific topic.
class TopicScoreStats {
  /// True if the peer is in our mesh for this topic.
  bool inMesh = false;

  /// Time when the peer was GRAFTed into the mesh for this topic. Null if not in mesh.
  DateTime? graftTime;

  /// Cumulative time the peer has been in the mesh for the current scoring interval.
  /// This is subject to caps and decay as per [PeerScoreParams.TopicScoreParams.timeInMeshQuantum].
  Duration meshTime = Duration.zero;

  /// Counter for first message deliveries from this peer in this topic (P3a).
  int firstMessageDeliveries = 0;

  /// Counter for messages delivered by this peer while in the mesh for this topic (P2).
  int meshMessageDeliveries = 0;

  /// True if the [meshMessageDeliveries] counter is active for the current refresh interval.
  /// This is set to true when the peer sends a message, and reset after [PeerScoreParams.TopicScoreParams.meshMessageDeliveriesDecay].
  bool meshMessageDeliveriesActive = false;

  /// Timestamp of when [meshMessageDeliveriesActive] was set to true.
  DateTime meshMessageDeliveriesActivation = DateTime.fromMillisecondsSinceEpoch(0);
  
  /// Counter for mesh message delivery failures from this peer in this topic (P2 penalty).
  int meshFailurePenalty = 0;

  /// Counter for invalid messages received from this peer in this topic (P3b penalty).
  int invalidMessageDeliveries = 0;

  /// Timestamp of the last successful message delivery from this peer in this topic.
  /// Used to check against [PeerScoreParams.TopicScoreParams.topicWeightCapGracePeriod] for P1 cap.
  DateTime lastSuccessfulDelivery = DateTime.fromMillisecondsSinceEpoch(0);


  TopicScoreStats();

  /// Resets the counters that are subject to decay or periodic refresh.
  /// Does not reset [inMesh], [graftTime], or [meshTime] as these persist or are handled differently.
  void resetCounters() {
    firstMessageDeliveries = 0;
    meshMessageDeliveries = 0;
    // meshMessageDeliveriesActive is managed by its own decay logic
    meshFailurePenalty = 0;
    invalidMessageDeliveries = 0;
  }
}

/// Represents the scoring state and statistics for a single peer.
class PeerScore {
  final PeerId peerId;
  final PeerScoreParams params;

  /// The current score for the peer.
  double score = 0.0;

  /// Per-topic statistics for the peer.
  /// topic_string -> TopicScoreStats
  final Map<String, TopicScoreStats> topicStats = {};

  /// IP colocation tracking. Set of IP addresses seen for this peer.
  final Set<String> knownIPs = {};

  /// True if the peer is currently IP-colocated with another active peer.
  bool ipColocated = false;

  /// Behavioral penalty counter (P6).
  int behaviourPenalty = 0;

  /// Global counter for invalid messages from this peer (P6).
  int invalidMessageDeliveries = 0;

  /// Value of the application-specific score component (P7).
  /// This is calculated by the function [PeerScoreParams.appSpecificScore].
  double appSpecificScoreValue = 0.0;

  /// Timestamp of the last score calculation. Used for score decay.
  DateTime lastUpdated;

  /// Timestamp until which the peer is graylisted. Null if not graylisted.
  /// A peer is graylisted if its score is below [PeerScoreParams.graylistThreshold].
  DateTime? graylistUntil;

  /// Clock to use for time-sensitive operations.
  final Clock _clock;

  // TODO: Review remaining fields from go-libp2p-pubsub/score.go PeerStats:
  // - firstMessageDeliveries: Now in TopicScoreStats.
  // - meshMessageDeliveries: Now in TopicScoreStats.
  // - meshFailurePenalty: Now in TopicScoreStats.
  // - invalidMessageDeliveries: Global counter added, per-topic in TopicScoreStats.
  // - applicationSpecificScore: Function is in params, value stored as appSpecificScoreValue.
  // - lastUpdated: Added.
  // - graylistUntil: Added.
  // - Other potential fields: connected (bool), P3b stats if more granular than counter.
  // - `sticky` flag for peers with sticky connections (exempt from scoring/pruning in some cases)

  PeerScore(this.peerId, this.params, {Clock? clock}) 
    : _clock = clock ?? const Clock(),
      lastUpdated = clock?.now() ?? DateTime.now();

  /// Retrieves or creates [TopicScoreStats] for a given topic.
  TopicScoreStats _getOrAddTopicStats(String topic) {
    return topicStats.putIfAbsent(topic, () => TopicScoreStats());
  }

  /// Recalculates the peer's score based on current stats and params.
  /// This is typically called periodically (e.g., by the heartbeat).
  void refreshScore() {
    final now = _clock.now();
    double currentRawScore = 0;

    // Apply score decay
    final timeSinceLastUpdate = now.difference(lastUpdated);
    
    // Calculate the number of decay intervals that have passed.
    final numIntervals = (params.decayInterval.inMilliseconds > 0)
        ? (timeSinceLastUpdate.inMilliseconds / params.decayInterval.inMilliseconds).floor()
        : 0;
    
    if (numIntervals > 0) {
      for (int i = 0; i < numIntervals; i++) {
        score *= params.scoreDecay;
        if (score.abs() < params.decayToZero) {
          score = 0; // Snap to zero if it's decaying towards it and falls below the threshold
        }
      }
    }
    
    // P7: Application-specific score
    if (params.appSpecificScore != null) {
      appSpecificScoreValue = params.appSpecificScore!(peerId);
      // P7 is directly added to the score at the end, after P1-P6 and P5 factor.
    } else {
      appSpecificScoreValue = 0.0;
    }

    double topicScoresTotal = 0;

    // P1-P4: Topic-based scores
    for (final topicEntry in topicStats.entries) {
      final topic = topicEntry.key;
      final tStats = topicEntry.value;
      final tParams = params.getTopicParams(topic);
      
      double currentTopicScore = 0;

      // P1: Time in Mesh
      if (tStats.inMesh) {
        // Update meshTime: Time elapsed since last update, or since graftTime if more recent.
        DateTime meshTimeReference = tStats.graftTime ?? lastUpdated;
        if (lastUpdated.isAfter(meshTimeReference)) {
            meshTimeReference = lastUpdated;
        }
        final meshDurationThisPeriod = now.difference(meshTimeReference);
        tStats.meshTime += meshDurationThisPeriod;

        final quantaInMesh = (tStats.meshTime.inMilliseconds / tParams.timeInMeshQuantum.inMilliseconds).floor();
        double p1Score = quantaInMesh * tParams.topicWeight;
        
        if (p1Score > tParams.timeInMeshCap) {
          p1Score = tParams.timeInMeshCap;
        }
        
        // P1 Cap Grace Period: If peer is in mesh but hasn't delivered messages recently,
        // P1 score is capped at 0.
        final timeSinceLastDelivery = now.difference(tStats.lastSuccessfulDelivery);
        if (timeSinceLastDelivery > tParams.topicWeightCapGracePeriod) {
          if (p1Score > 0) { // Only cap if it was positive
             p1Score = 0;
          }
        }
        currentTopicScore += p1Score;
        
        // "Consume" the mesh time that has been scored by resetting meshTime based on quanta.
        // This ensures we only score new mesh time in the next interval.
        // Or, more simply, cap meshTime at the max scorable duration if not resetting.
        // The spec implies meshTime is a cumulative counter for the current scoring period,
        // reset/decayed at the end of the period or when P1 cap is hit.
        // Let's adjust tStats.meshTime to reflect only the unscored portion for the next round,
        // or cap it if it exceeds a very large value to prevent overflow.
        // For now, we'll let it accumulate and rely on the cap.
        // The decay of P1 happens via the global score decay.
      }
      
      // P3a: First Message Deliveries (referred to as P2 in some of our earlier comments)
      // Score for delivering the first message successfully.
      double p3aScore = tStats.firstMessageDeliveries * tParams.firstMessageDeliveriesWeight;
      if (p3aScore > tParams.firstMessageDeliveriesCap) {
        p3aScore = tParams.firstMessageDeliveriesCap;
      }
      // TODO: Apply tParams.firstMessageDeliveriesDecay to tStats.firstMessageDeliveries counter
      // if decay is < 1.0. Typically this counter is reset periodically.
      currentTopicScore += p3aScore;

      // P2: Mesh Message Deliveries (referred to as P3 in some of our earlier comments)
      // Score for messages delivered whilst in the mesh.
      if (tStats.meshMessageDeliveriesActive) {
        if (now.difference(tStats.meshMessageDeliveriesActivation) > tParams.meshMessageDeliveriesActivationWindow) {
          tStats.meshMessageDeliveriesActive = false;
          tStats.meshMessageDeliveries = 0; // Reset counter after activation window expires
        } else {
          // TODO: Apply tParams.meshMessageDeliveriesWindowDecay to tStats.meshMessageDeliveries counter
          // if decay is < 1.0, for gradual decay within the window.
          double p2Score = tStats.meshMessageDeliveries * tParams.meshMessageDeliveriesWeight;
          if (p2Score > tParams.meshMessageDeliveriesCap) {
            p2Score = tParams.meshMessageDeliveriesCap;
          }
          currentTopicScore += p2Score;
        }
      }
      // TODO: Apply tParams.meshMessageDeliveriesDecay if this counter is meant to decay outside the active window.
      // For now, it's reset when the window expires or by resetCounters().

      // P4 / P2 Penalty: Mesh Message Delivery Failure Penalty
      // Penalty for failing to deliver messages requested via IWANT.
      double p4Score = tStats.meshFailurePenalty * tParams.meshFailurePenaltyWeight;
      // TODO: Apply tParams.meshFailurePenaltyDecay to tStats.meshFailurePenalty counter
      // if decay is < 1.0. Typically this counter is reset periodically.
      currentTopicScore += p4Score;
      
      // P4 / P3b Penalty: Invalid Message Deliveries Penalty (per topic)
      // Penalty for sending invalid messages on this topic.
      double p3bScore = tStats.invalidMessageDeliveries * tParams.invalidMessageDeliveriesWeight;
      // TODO: Apply tParams.invalidMessageDeliveriesDecay to tStats.invalidMessageDeliveries counter
      // if decay is < 1.0. Typically this counter is reset periodically.
      currentTopicScore += p3bScore;
      
      topicScoresTotal += currentTopicScore;
    }
    currentRawScore = topicScoresTotal;

    // P5: IP Colocation Factor
    // Applied if the sum of topic scores (currentRawScore) is positive.
    if (ipColocated && currentRawScore > 0) {
      currentRawScore *= params.ipColocationFactor;
      // As per spec, score is not allowed to become negative as a result of P5.
      // Since ipColocationFactor should be >= 0, this check is mainly for safety.
      if (currentRawScore < 0) {
        currentRawScore = 0;
      }
    }
    
    // P6: Behavioural Penalty
    // This is a global penalty not tied to a specific topic.
    // The `behaviourPenalty` counter accumulates penalties from `addPenalty()`.
    // We apply decay to the counter itself.
    final numDecayIntervalsForP6 = (now.difference(lastUpdated).inMilliseconds / params.decayInterval.inMilliseconds).floor();
    for (int i = 0; i < numDecayIntervalsForP6; i++) {
        behaviourPenalty = (behaviourPenalty * params.behaviourPenaltyDecay).round(); // Assuming behaviourPenalty is an int counter
    }
    
    double p6PenaltyScore = behaviourPenalty * params.behaviourPenaltyWeight;
    if (p6PenaltyScore < params.behaviourPenaltyCap) { // cap is negative, so check if score is "more negative"
      p6PenaltyScore = params.behaviourPenaltyCap;
    }
    // P6 is added to the overall score, not just topic scores.
    // The spec implies P6 is a direct hit on the score.

    // Combine scores:
    // score (already decayed) = score + topicScoreSumWithP5Factor + P6_penalty + P7_app_score
    score += currentRawScore + p6PenaltyScore + appSpecificScoreValue;


    // Apply score caps and floors
    if (score > params.scoreMax) {
      score = params.scoreMax;
    } else if (score < params.scoreMin) {
      score = params.scoreMin;
    }

    // Update graylist status
    if (score < params.graylistThreshold) {
      if (graylistUntil == null) { // Not currently graylisted
        graylistUntil = now.add(params.graylistDuration);
      }
      // If already graylisted, refreshScore doesn't extend it unless score drops further
      // or specific conditions are met (not detailed here, assume simple threshold).
    } else {
      graylistUntil = null; // No longer meets graylist criteria
    }

    lastUpdated = now;
    
    // After calculating scores, reset counters that are subject to decay/refresh for the next period.
    // This was previously in a separate `resetCounters` method in PeerScore,
    // but it's often called as part of the refresh cycle.
    // For now, we'll assume TopicScoreStats.resetCounters() is called appropriately.
    // And global counters like `behaviourPenalty` are managed by their specific logic.
    // `invalidMessageDeliveries` (global) is a lifetime counter.
    // `meshTime` in TopicScoreStats is managed with its quantum.

    // TODO: Call TopicScoreStats.resetCounters() for each topic if appropriate here.
    // TODO: Decay meshMessageDeliveriesActive in TopicScoreStats - this is handled by its own window logic.

    // After all scores for the period are calculated and `score` is updated,
    // reset the per-topic counters for the next scoring period.
    for (final tStats in topicStats.values) {
        // Reset counters like firstMessageDeliveries, meshMessageDeliveries (if inactive), 
        // meshFailurePenalty, invalidMessageDeliveries (topic-specific).
        // meshTime is cumulative for the current P1 calculation window and isn't reset here,
        // its contribution is based on quanta.
        tStats.resetCounters();
    }
    // Note: Global `invalidMessageDeliveries` (for P6) is a lifetime counter.
    // `behaviourPenalty` counter decay is handled within P6 calculation.

    print('PeerScore (${peerId.toBase58()}): Refreshed score. Current: $score, LastUpdated: $lastUpdated');
  }

  /// Adds a penalty for misbehavior.
  void addPenalty(int penalty) {
    behaviourPenalty += penalty;
    // TODO: Consider if refreshScore should be called immediately or deferred.
  }

  /// Resets the behavioral penalty.
  void resetPenalty() {
    behaviourPenalty = 0;
  }

  // TODO: Add methods for:
  // - addTopicStats(String topic, ...params for specific stats...) // Covered by _getOrAddTopicStats and specific record methods
  // - addIP(String ip)
  // - setIPColocated(bool isColocated)
  // - recordMessageDelivery(...) // Covered by more specific methods below
  // - recordInvalidMessage(...)
  // - recordGraft(...)
  // - recordPrune(...)
  // - etc., corresponding to events that affect the score.

  /// Records an IP address associated with this peer.
  void addIP(String ip) {
    knownIPs.add(ip);
    // IP colocation status is typically updated by an external process
    // that checks all peers' IPs.
  }

  /// Sets the IP colocation status for this peer.
  /// This is usually called by an external IP colocation detection mechanism.
  void setIPColocated(bool isColocated) {
    ipColocated = isColocated;
  }

  /// Records a GRAFT for a specific topic.
  void recordGraft(String topic) {
    final stats = _getOrAddTopicStats(topic);
    if (stats.inMesh) {
      return; // Already in mesh
    }
    stats.inMesh = true;
    final now = _clock.now();
    stats.graftTime = now;
    // Give the peer a fresh grace period for P1 cap by setting lastSuccessfulDelivery
    stats.lastSuccessfulDelivery = now; 
    // meshTime starts accumulating from now.
  }

  /// Records a PRUNE for a specific topic.
  void recordPrune(String topic) {
    final stats = _getOrAddTopicStats(topic);
    if (!stats.inMesh) {
      return; // Not in mesh
    }
    stats.inMesh = false;
    if (stats.graftTime != null) {
      final now = _clock.now();
      final durationInMesh = now.difference(stats.graftTime!);
      stats.meshTime += durationInMesh; // Add the session's mesh time
      // Cap meshTime per scoring interval in refreshScore() using timeInMeshQuantum
    }
    stats.graftTime = null;
    // Other mesh-related stats like meshMessageDeliveries might be reset or decayed here
    // or in refreshScore, depending on the specific decay logic.
    // For now, meshMessageDeliveriesActive is reset on its own decay.
  }

  /// Records the first delivery of a message from this peer for a given topic. (P3a)
  void recordFirstMessageDelivery(String topic) {
    final stats = _getOrAddTopicStats(topic);
    stats.firstMessageDeliveries++;
    stats.lastSuccessfulDelivery = _clock.now();
  }

  /// Records a message delivery from this peer while in the mesh for a given topic. (P2)
  void recordMeshMessageDelivery(String topic) {
    final stats = _getOrAddTopicStats(topic);
    if (!stats.inMesh) {
      return; // Not in mesh, this shouldn't count for P2.
    }
    stats.meshMessageDeliveries++;
    stats.meshMessageDeliveriesActive = true;
    final now = _clock.now();
    stats.meshMessageDeliveriesActivation = now;
    stats.lastSuccessfulDelivery = now;
  }
  
  /// Records a failure to deliver a message that was expected from this peer
  /// while in the mesh for a given topic. (P2 penalty)
  void recordMeshMessageFailure(String topic) {
    final stats = _getOrAddTopicStats(topic);
    if (!stats.inMesh) {
      return; // Not in mesh, this penalty doesn't apply.
    }
    stats.meshFailurePenalty++;
  }

  /// Records an invalid message received from this peer. (P3b penalty & P6)
  void recordInvalidMessage(String topic) {
    final stats = _getOrAddTopicStats(topic);
    stats.invalidMessageDeliveries++;
    invalidMessageDeliveries++; // Global counter for P6
  }

  /// Resets counters that are subject to decay or periodic refresh.
  /// This is typically called after scores are computed in [refreshScore].
  void resetCounters() {
    // Reset per-topic counters
    for (final topicStat in topicStats.values) {
      topicStat.resetCounters();
    }
    // Reset global peer counters (behaviourPenalty is managed by addPenalty/resetPenalty)
    // invalidMessageDeliveries is a lifetime counter for P6, not reset here.
    // appSpecificScoreValue is recalculated in refreshScore.
    // meshTime in TopicScoreStats is also managed within refreshScore based on quantum.
  }
}

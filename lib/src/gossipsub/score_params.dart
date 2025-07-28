import 'package:dart_libp2p/core/peer/peer_id.dart'; // Needed for AppSpecificScore function type

/// Defines parameters for scoring within a specific topic.
class TopicScoreParams {
  /// Base weight for participating in the topic (P1 component).
  final double topicWeight;

  /// Quantum for time in mesh calculation (P1 component).
  final Duration timeInMeshQuantum;
  /// Cap for score from time in mesh (P1 component).
  final double timeInMeshCap;
  /// Grace period after which the P1 cap is applied if no messages are seen.
  final Duration topicWeightCapGracePeriod;

  /// Weight for first message deliveries in this topic (P3a component).
  final double firstMessageDeliveriesWeight;
  /// Decay factor for first message deliveries score (P3a component).
  final double firstMessageDeliveriesDecay;
  /// Cap for score from first message deliveries (P3a component).
  final double firstMessageDeliveriesCap;

  /// Weight for mesh message deliveries in this topic (P2 component).
  final double meshMessageDeliveriesWeight;
  /// Decay factor for mesh message deliveries score (P2 component).
  final double meshMessageDeliveriesDecay;
  /// Threshold for activating mesh message deliveries score (P2 component).
  final int meshMessageDeliveriesThreshold;
  /// Cap for score from mesh message deliveries (P2 component).
  final double meshMessageDeliveriesCap;
  /// Activation window for mesh message deliveries (P2 component).
  final Duration meshMessageDeliveriesActivationWindow;
  /// Decay for the mesh message deliveries counter itself.
  final double meshMessageDeliveriesWindowDecay;


  /// Penalty for mesh message delivery failures in this topic (P2 penalty).
  final double meshFailurePenaltyWeight;
  /// Decay factor for mesh failure penalty (P2 penalty).
  final double meshFailurePenaltyDecay;

  /// Penalty for invalid messages in this topic (P3b penalty).
  final double invalidMessageDeliveriesWeight;
  /// Decay factor for invalid message penalty (P3b penalty).
  final double invalidMessageDeliveriesDecay;

  const TopicScoreParams({
    this.topicWeight = 0.0,
    this.timeInMeshQuantum = const Duration(seconds: 1),
    this.timeInMeshCap = 3600.0, // e.g., 1 hour worth of quantum
    this.topicWeightCapGracePeriod = const Duration(hours: 1),

    this.firstMessageDeliveriesWeight = 0.0,
    this.firstMessageDeliveriesDecay = 1.0, // No decay by default
    this.firstMessageDeliveriesCap = 2000.0,

    this.meshMessageDeliveriesWeight = 0.0,
    this.meshMessageDeliveriesDecay = 1.0, // No decay by default
    this.meshMessageDeliveriesThreshold = 0,
    this.meshMessageDeliveriesCap = 100.0,
    this.meshMessageDeliveriesActivationWindow = const Duration(minutes: 1),
    this.meshMessageDeliveriesWindowDecay = 1.0, // No decay by default

    this.meshFailurePenaltyWeight = 0.0,
    this.meshFailurePenaltyDecay = 1.0, // No decay by default

    this.invalidMessageDeliveriesWeight = 0.0,
    this.invalidMessageDeliveriesDecay = 1.0, // No decay by default
  });

  static TopicScoreParams get defaultTopicParams => const TopicScoreParams();
}


/// Defines the parameters that control the peer scoring mechanism in GossipSub.
/// These parameters are based on the GossipSub v1.1 specification.
class PeerScoreParams {
  /// Default parameters for topics that don't have specific overrides.
  final TopicScoreParams defaultTopicParams;
  /// Specific parameter overrides for topics, keyed by topic string.
  final Map<String, TopicScoreParams> topicParamsOverrides;

  // --- Global Parameters (not topic-specific) ---
  /// Application-specific score function. (P7)
  /// Allows the application to provide a custom score component.
  /// The function takes a PeerId and returns a double score.
  final double Function(PeerId peerId)? appSpecificScore;

  /// IP colocation factor. (P5)
  /// Multiplicative factor applied if a peer is IP-colocated and their topic score sum is positive.
  /// Value should be <= 1.0 (e.g., 0.75 for a 25% penalty).
  final double ipColocationFactor;
  final int ipColocationFactorThreshold; // Min number of peers on IP to trigger penalty
  final double ipColocationFactorWhitelist; // TODO: Implement IP whitelist functionality

  /// Decay interval for the global score and some counters.
  final Duration decayInterval;
  /// General decay factor for the score per interval.
  final double scoreDecay;
  /// Decay-to-zero factor. Scores below this (in magnitude) are rounded to zero.
  final double decayToZero;

  /// Time to remember a message delivery in seconds (for P2, P3).
  final Duration deliveryRecordTTL; // This might become topic-specific if P2/P3 decay is topic-specific

  /// Score caps.
  final double scoreMin; // Global score minimum
  final double scoreMax; // Global score maximum (though often implicit through positive contributions)

  /// Score threshold to be graylisted (blocked from propagation).
  final double graylistThreshold;
  /// Time for which a peer is graylisted if their score drops below GraylistThreshold.
  final Duration graylistDuration;

  /// Time window for opportunistic grafting.
  final Duration opportunisticGraftThreshold; // Time since last graft to consider opportunistic

  /// Global weight for behavioral penalties (P6).
  final double behaviourPenaltyWeight;
  /// Decay for behavioral penalties (P6).
  final double behaviourPenaltyDecay;
  /// Cap for behavioral penalties (P6).
  final double behaviourPenaltyCap;


  const PeerScoreParams({
    TopicScoreParams? defaultTopicParams,
    this.topicParamsOverrides = const {},
    this.appSpecificScore,
    this.ipColocationFactor = 0.75, // Default to a 25% penalty factor
    this.ipColocationFactorThreshold = 2,
    this.ipColocationFactorWhitelist = 0.0, // Placeholder
    this.decayInterval = const Duration(seconds: 1),
    this.scoreDecay = 0.99,
    this.decayToZero = 0.01,
    this.deliveryRecordTTL = const Duration(minutes: 2),
    this.scoreMin = -1000.0,
    this.scoreMax = 1000.0,
    this.graylistThreshold = -100.0,
    this.graylistDuration = const Duration(minutes: 1),
    this.opportunisticGraftThreshold = const Duration(minutes: 1),
    this.behaviourPenaltyWeight = -10.0,
    this.behaviourPenaltyDecay = 0.99,
    this.behaviourPenaltyCap = -100.0,
  }) : defaultTopicParams = defaultTopicParams ?? const TopicScoreParams();

  static PeerScoreParams get defaultParams => PeerScoreParams(defaultTopicParams: TopicScoreParams.defaultTopicParams);

  /// Helper to get the effective TopicScoreParams for a given topic string.
  TopicScoreParams getTopicParams(String topic) {
    return topicParamsOverrides[topic] ?? defaultTopicParams;
  }
}

/// Defines the score thresholds for GossipSub peer management.
class PeerScoreThresholds {
  /// Score threshold to be accepted into the mesh.
  final double publishThreshold; // Renamed from DScore in GossipSubParams for clarity here

  /// Score threshold to be chosen as a gossip target (IHAVE recipient).
  final double gossipThreshold;

  /// Score threshold to be accepted for opportunistic grafting.
  final double opportunisticGraftThresholdValue; // Renamed to avoid conflict with Duration

  const PeerScoreThresholds({
    this.publishThreshold = -50.0, // Peers must have at least this score to receive our messages
    this.gossipThreshold = -20.0,  // We only gossip to peers with at least this score
    this.opportunisticGraftThresholdValue = 5.0, // We only opportunistically graft to peers with at least this score
  });

  static PeerScoreThresholds get defaultThresholds => const PeerScoreThresholds();
}

import 'dart:io' show InternetAddress;
import 'dart:math' as math;

import 'package:dart_libp2p/core/peer/peer_id.dart';

/// The default [PeerScoreParams.decayInterval] (go-libp2p-pubsub's
/// `DefaultDecayInterval`).
const Duration defaultDecayInterval = Duration(seconds: 1);

/// The default [PeerScoreParams.decayToZero] (go-libp2p-pubsub's
/// `DefaultDecayToZero`).
const double defaultDecayToZero = 0.01;

/// The decay factor that takes a counter from 1 to [decayToZero] in [decay],
/// decaying once every [base] (go-libp2p-pubsub's
/// `ScoreParameterDecayWithBase`).
double scoreParameterDecay(Duration decay,
    {Duration base = defaultDecayInterval, double decayToZero = defaultDecayToZero}) {
  final ticks = decay.inMicroseconds / base.inMicroseconds;
  return math.pow(decayToZero, 1 / ticks).toDouble();
}

bool _isInvalidNumber(double x) => x.isNaN || x.isInfinite;

/// The score thresholds of GossipSub, as go-libp2p-pubsub's
/// `PeerScoreThresholds`.
class PeerScoreThresholds {
  /// Below this score, a peer gets no gossip from us, and its gossip (IHAVE
  /// and IWANT) is ignored. Must be <= 0.
  final double gossipThreshold;

  /// Below this score, a peer gets none of our published messages (flood
  /// publish and fanout). Must be <= [gossipThreshold].
  final double publishThreshold;

  /// Below this score, the RPCs of a peer are ignored entirely. Must be <=
  /// [publishThreshold].
  final double graylistThreshold;

  /// The Peer Exchange of a PRUNE is used only if its sender's score is at
  /// least this. Must be >= 0.
  final double acceptPXThreshold;

  /// When the median score of a topic's mesh is below this, the heartbeat
  /// opportunistically GRAFTs better peers. Must be >= 0.
  final double opportunisticGraftThreshold;

  const PeerScoreThresholds({
    this.gossipThreshold = 0,
    this.publishThreshold = 0,
    this.graylistThreshold = 0,
    this.acceptPXThreshold = 0,
    this.opportunisticGraftThreshold = 0,
  });

  /// Throws an [ArgumentError] if the thresholds are not consistent, as
  /// go-libp2p-pubsub's `PeerScoreThresholds.validate`.
  void validate() {
    if (gossipThreshold > 0 || _isInvalidNumber(gossipThreshold)) {
      throw ArgumentError('invalid gossip threshold; it must be <= 0 and a valid number');
    }
    if (publishThreshold > 0 || publishThreshold > gossipThreshold || _isInvalidNumber(publishThreshold)) {
      throw ArgumentError('invalid publish threshold; it must be <= 0 and <= gossip threshold and a valid number');
    }
    if (graylistThreshold > 0 || graylistThreshold > publishThreshold || _isInvalidNumber(graylistThreshold)) {
      throw ArgumentError('invalid graylist threshold; it must be <= 0 and <= publish threshold and a valid number');
    }
    if (acceptPXThreshold < 0 || _isInvalidNumber(acceptPXThreshold)) {
      throw ArgumentError('invalid accept PX threshold; it must be >= 0 and a valid number');
    }
    if (opportunisticGraftThreshold < 0 || _isInvalidNumber(opportunisticGraftThreshold)) {
      throw ArgumentError('invalid opportunistic grafting threshold; it must be >= 0 and a valid number');
    }
  }
}

/// The parameters of peer scoring, as go-libp2p-pubsub's `PeerScoreParams`.
///
/// The score of a peer is
///
///     min(sum over scored topics of topicWeight * topic score, topicScoreCap)
///       + P5 (app-specific) + P6 (IP colocation) + P7 (behaviour penalty)
///
/// Only the topics in [topics] are scored.
class PeerScoreParams {
  /// The score parameters of each scored topic.
  final Map<String, TopicScoreParams> topics;

  /// The cap on the sum of the topic scores; 0 for no cap. Must be >= 0.
  final double topicScoreCap;

  /// P5: the application-specific score of a peer, multiplied by
  /// [appSpecificWeight]. Defaults to 0 for every peer.
  final double Function(PeerId peer) appSpecificScore;
  final double appSpecificWeight;

  /// P6: the IP colocation penalty. When more than
  /// [ipColocationFactorThreshold] peers connect from one IP (or IPv6 /64),
  /// each gets `weight * (peers - threshold)^2`. The weight must be <= 0.
  final double ipColocationFactorWeight;
  final int ipColocationFactorThreshold;

  /// IP ranges (CIDR, such as `10.0.0.0/8`) not subject to P6.
  final List<String> ipColocationFactorWhitelist;

  /// P7: the behaviour penalty, `weight * (penalty - threshold)^2` when the
  /// penalty counter is above [behaviourPenaltyThreshold]. The weight must
  /// be <= 0; the counter decays by [behaviourPenaltyDecay] each
  /// [decayInterval].
  final double behaviourPenaltyWeight;
  final double behaviourPenaltyThreshold;
  final double behaviourPenaltyDecay;

  /// How often counters decay. Must be at least 1 s.
  final Duration decayInterval;

  /// A decayed counter below this is set to 0. Must be in (0, 1).
  final double decayToZero;

  /// How long the score of a disconnected peer with a score <= 0 is kept,
  /// so that it cannot clear its penalties by reconnecting.
  final Duration retainScore;

  /// How long message delivery records are kept (go-libp2p-pubsub's
  /// `SeenMsgTTL`, default the seen-messages TTL).
  final Duration seenMsgTTL;

  const PeerScoreParams({
    this.topics = const {},
    this.topicScoreCap = 0,
    this.appSpecificScore = _zeroScore,
    this.appSpecificWeight = 0,
    this.ipColocationFactorWeight = 0,
    this.ipColocationFactorThreshold = 1,
    this.ipColocationFactorWhitelist = const [],
    this.behaviourPenaltyWeight = 0,
    this.behaviourPenaltyThreshold = 0,
    this.behaviourPenaltyDecay = 0.99,
    this.decayInterval = defaultDecayInterval,
    this.decayToZero = defaultDecayToZero,
    this.retainScore = const Duration(hours: 1),
    this.seenMsgTTL = const Duration(minutes: 2),
  });

  static double _zeroScore(PeerId peer) => 0;

  /// Throws an [ArgumentError] if the parameters are not valid, as
  /// go-libp2p-pubsub's `PeerScoreParams.validate`.
  void validate() {
    for (final entry in topics.entries) {
      try {
        entry.value.validate();
      } on ArgumentError catch (e) {
        throw ArgumentError('invalid score parameters for topic ${entry.key}: ${e.message}');
      }
    }
    if (topicScoreCap < 0 || _isInvalidNumber(topicScoreCap)) {
      throw ArgumentError('invalid topic score cap; must be positive (or 0 for no cap) and a valid number');
    }
    if (ipColocationFactorWeight > 0 || _isInvalidNumber(ipColocationFactorWeight)) {
      throw ArgumentError('invalid IPColocationFactorWeight; must be negative (or 0 to disable) and a valid number');
    }
    if (ipColocationFactorWeight != 0 && ipColocationFactorThreshold < 1) {
      throw ArgumentError('invalid IPColocationFactorThreshold; must be at least 1');
    }
    for (final cidr in ipColocationFactorWhitelist) {
      if (IpNet.tryParse(cidr) == null) {
        throw ArgumentError('invalid IPColocationFactorWhitelist entry: $cidr');
      }
    }
    if (behaviourPenaltyWeight > 0 || _isInvalidNumber(behaviourPenaltyWeight)) {
      throw ArgumentError('invalid BehaviourPenaltyWeight; must be negative (or 0 to disable) and a valid number');
    }
    if (behaviourPenaltyWeight != 0 &&
        (behaviourPenaltyDecay <= 0 || behaviourPenaltyDecay >= 1 || _isInvalidNumber(behaviourPenaltyDecay))) {
      throw ArgumentError('invalid BehaviourPenaltyDecay; must be between 0 and 1');
    }
    if (behaviourPenaltyThreshold < 0 || _isInvalidNumber(behaviourPenaltyThreshold)) {
      throw ArgumentError('invalid BehaviourPenaltyThreshold; must be >= 0 and a valid number');
    }
    if (decayInterval < const Duration(seconds: 1)) {
      throw ArgumentError('invalid DecayInterval; must be at least 1s');
    }
    if (decayToZero <= 0 || decayToZero >= 1 || _isInvalidNumber(decayToZero)) {
      throw ArgumentError('invalid DecayToZero; must be between 0 and 1');
    }
  }
}

/// The score parameters of one topic, as go-libp2p-pubsub's
/// `TopicScoreParams`. The topic score is
///
///     P1 * timeInMeshWeight + P2 * firstMessageDeliveriesWeight
///       + P3 * meshMessageDeliveriesWeight + P3b * meshFailurePenaltyWeight
///       + P4 * invalidMessageDeliveriesWeight
///
/// and is multiplied by [topicWeight] in the peer's score.
class TopicScoreParams {
  /// The weight of the topic in the score. Must be >= 0.
  final double topicWeight;

  /// P1: time in the mesh, in [timeInMeshQuantum]s, capped to
  /// [timeInMeshCap]. The weight must be >= 0.
  final double timeInMeshWeight;
  final Duration timeInMeshQuantum;
  final double timeInMeshCap;

  /// P2: the messages that the peer delivered first, with decay, capped.
  /// The weight must be >= 0.
  final double firstMessageDeliveriesWeight;
  final double firstMessageDeliveriesDecay;
  final double firstMessageDeliveriesCap;

  /// P3: the deficit of mesh message deliveries. A mesh peer that delivered
  /// (first, or within [meshMessageDeliveriesWindow] of the first delivery)
  /// fewer than [meshMessageDeliveriesThreshold] messages, once it has been
  /// in the mesh for [meshMessageDeliveriesActivation], gets
  /// `weight * deficit^2`. The weight must be <= 0.
  final double meshMessageDeliveriesWeight;
  final double meshMessageDeliveriesDecay;
  final double meshMessageDeliveriesCap;
  final double meshMessageDeliveriesThreshold;
  final Duration meshMessageDeliveriesWindow;
  final Duration meshMessageDeliveriesActivation;

  /// P3b: a sticky penalty for a mesh delivery deficit at the time the peer
  /// left the mesh. The weight must be <= 0.
  final double meshFailurePenaltyWeight;
  final double meshFailurePenaltyDecay;

  /// P4: invalid messages, `weight * count^2`. The weight must be <= 0.
  final double invalidMessageDeliveriesWeight;
  final double invalidMessageDeliveriesDecay;

  const TopicScoreParams({
    this.topicWeight = 0,
    this.timeInMeshWeight = 0,
    this.timeInMeshQuantum = const Duration(seconds: 1),
    this.timeInMeshCap = 0,
    this.firstMessageDeliveriesWeight = 0,
    this.firstMessageDeliveriesDecay = 0.5,
    this.firstMessageDeliveriesCap = 0,
    this.meshMessageDeliveriesWeight = 0,
    this.meshMessageDeliveriesDecay = 0.5,
    this.meshMessageDeliveriesCap = 0,
    this.meshMessageDeliveriesThreshold = 0,
    this.meshMessageDeliveriesWindow = Duration.zero,
    this.meshMessageDeliveriesActivation = const Duration(seconds: 1),
    this.meshFailurePenaltyWeight = 0,
    this.meshFailurePenaltyDecay = 0.5,
    this.invalidMessageDeliveriesWeight = 0,
    this.invalidMessageDeliveriesDecay = 0.5,
  });

  /// Throws an [ArgumentError] if the parameters are not valid, as
  /// go-libp2p-pubsub's `TopicScoreParams.validate`.
  void validate() {
    if (topicWeight < 0 || _isInvalidNumber(topicWeight)) {
      throw ArgumentError('invalid topic weight; must be >= 0 and a valid number');
    }

    if (timeInMeshQuantum <= Duration.zero) {
      throw ArgumentError('invalid TimeInMeshQuantum; must be positive');
    }
    if (timeInMeshWeight < 0 || _isInvalidNumber(timeInMeshWeight)) {
      throw ArgumentError('invalid TimeInMeshWeight; must be positive (or 0 to disable) and a valid number');
    }
    if (timeInMeshWeight != 0 && (timeInMeshCap <= 0 || _isInvalidNumber(timeInMeshCap))) {
      throw ArgumentError('invalid TimeInMeshCap; must be positive and a valid number');
    }

    if (firstMessageDeliveriesWeight < 0 || _isInvalidNumber(firstMessageDeliveriesWeight)) {
      throw ArgumentError('invalid FirstMessageDeliveriesWeight; must be positive (or 0 to disable) and a valid number');
    }
    if (firstMessageDeliveriesWeight != 0 && !_isDecay(firstMessageDeliveriesDecay)) {
      throw ArgumentError('invalid FirstMessageDeliveriesDecay; must be between 0 and 1');
    }
    if (firstMessageDeliveriesWeight != 0 &&
        (firstMessageDeliveriesCap <= 0 || _isInvalidNumber(firstMessageDeliveriesCap))) {
      throw ArgumentError('invalid FirstMessageDeliveriesCap; must be positive and a valid number');
    }

    if (meshMessageDeliveriesWeight > 0 || _isInvalidNumber(meshMessageDeliveriesWeight)) {
      throw ArgumentError('invalid MeshMessageDeliveriesWeight; must be negative (or 0 to disable) and a valid number');
    }
    if (meshMessageDeliveriesWeight != 0 && !_isDecay(meshMessageDeliveriesDecay)) {
      throw ArgumentError('invalid MeshMessageDeliveriesDecay; must be between 0 and 1');
    }
    if (meshMessageDeliveriesWeight != 0 &&
        (meshMessageDeliveriesCap <= 0 || _isInvalidNumber(meshMessageDeliveriesCap))) {
      throw ArgumentError('invalid MeshMessageDeliveriesCap; must be positive and a valid number');
    }
    if (meshMessageDeliveriesWeight != 0 &&
        (meshMessageDeliveriesThreshold <= 0 || _isInvalidNumber(meshMessageDeliveriesThreshold))) {
      throw ArgumentError('invalid MeshMessageDeliveriesThreshold; must be positive and a valid number');
    }
    if (meshMessageDeliveriesWindow < Duration.zero) {
      throw ArgumentError('invalid MeshMessageDeliveriesWindow; must be non-negative');
    }
    if (meshMessageDeliveriesWeight != 0 && meshMessageDeliveriesActivation < const Duration(seconds: 1)) {
      throw ArgumentError('invalid MeshMessageDeliveriesActivation; must be at least 1s');
    }

    if (meshFailurePenaltyWeight > 0 || _isInvalidNumber(meshFailurePenaltyWeight)) {
      throw ArgumentError('invalid MeshFailurePenaltyWeight; must be negative (or 0 to disable) and a valid number');
    }
    if (meshFailurePenaltyWeight != 0 && !_isDecay(meshFailurePenaltyDecay)) {
      throw ArgumentError('invalid MeshFailurePenaltyDecay; must be between 0 and 1');
    }

    if (invalidMessageDeliveriesWeight > 0 || _isInvalidNumber(invalidMessageDeliveriesWeight)) {
      throw ArgumentError('invalid InvalidMessageDeliveriesWeight; must be negative (or 0 to disable) and a valid number');
    }
    if (!_isDecay(invalidMessageDeliveriesDecay)) {
      throw ArgumentError('invalid InvalidMessageDeliveriesDecay; must be between 0 and 1');
    }
  }

  static bool _isDecay(double d) => d > 0 && d < 1 && !_isInvalidNumber(d);
}

/// An IP range in CIDR notation, such as `192.168.0.0/16` or `fd00::/8`.
class IpNet {
  final List<int> _prefix;
  final int _bits;

  IpNet._(this._prefix, this._bits);

  /// Parses [cidr], or returns null if it is not a valid CIDR range.
  static IpNet? tryParse(String cidr) {
    final slash = cidr.indexOf('/');
    if (slash < 0) return null;
    final address = InternetAddress.tryParse(cidr.substring(0, slash));
    final bits = int.tryParse(cidr.substring(slash + 1));
    if (address == null || bits == null || bits < 0 || bits > address.rawAddress.length * 8) {
      return null;
    }
    return IpNet._(address.rawAddress, bits);
  }

  /// Whether [ip] is in this range.
  bool contains(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.rawAddress.length != _prefix.length) return false;
    final raw = address.rawAddress;
    for (var bit = 0; bit < _bits; bit++) {
      final mask = 0x80 >> (bit % 8);
      if ((raw[bit ~/ 8] & mask) != (_prefix[bit ~/ 8] & mask)) return false;
    }
    return true;
  }
}

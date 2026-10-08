import 'dart:async';
import 'dart:collection';
import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import 'score_params.dart';

final _log = Logger('PeerScore');

/// Why a message was not accepted, for [PeerScore.rejectMessage]; as the
/// reject reasons of go-libp2p-pubsub that matter to scoring.
enum RejectReason {
  /// The message failed the structure or signature checks. Its ID cannot be
  /// trusted, so only the peer that sent it is penalised.
  invalidSignature,

  /// A validator rejected the message: the sender, and every peer that
  /// forwards the message later, is penalised.
  validationFailed,

  /// A validator ignored the message, or it timed out: no penalty.
  validationIgnored,

  /// Validation was throttled: no penalty, as the message may be valid.
  validationThrottled,
}

/// The scoring counters of a peer in a topic, as go-libp2p-pubsub's
/// `topicStats`.
class TopicScoreStats {
  /// Whether the peer is in our mesh for the topic.
  bool inMesh = false;

  /// When the peer was (last) GRAFTed; valid while [inMesh].
  DateTime graftTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// The time the peer has been in the mesh, updated at each decay.
  Duration meshTime = Duration.zero;

  /// P2 counter.
  double firstMessageDeliveries = 0;

  /// P3 counter.
  double meshMessageDeliveries = 0;

  /// Whether the peer has been in the mesh long enough for P3 to apply.
  bool meshMessageDeliveriesActive = false;

  /// P3b counter.
  double meshFailurePenalty = 0;

  /// P4 counter.
  double invalidMessageDeliveries = 0;
}

class _PeerStats {
  bool connected = false;
  DateTime expire = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, TopicScoreStats> topics = {};
  List<String> ips = const [];
  final Map<String, bool> ipWhitelist = {};
  double behaviourPenalty = 0;
}

enum _DeliveryStatus { unknown, valid, invalid, ignored, throttled }

class _DeliveryRecord {
  _DeliveryStatus status = _DeliveryStatus.unknown;
  final DateTime firstSeen;
  DateTime? validated;
  Set<PeerId> peers = {};
  _DeliveryRecord(this.firstSeen);
}

/// A snapshot of a peer's score and its components, as go-libp2p-pubsub's
/// `PeerScoreSnapshot`.
class PeerScoreSnapshot {
  final double score;
  final Map<String, TopicScoreStats> topics;
  final double appSpecificScore;
  final double ipColocationFactor;
  final double behaviourPenalty;

  PeerScoreSnapshot(this.score, this.topics, this.appSpecificScore,
      this.ipColocationFactor, this.behaviourPenalty);
}

/// Peer scoring for GossipSub v1.1, as go-libp2p-pubsub's `peerScore`.
///
/// The router reports peer and message events to it (the tracer methods of
/// `peerScore` in Go); counters decay every [PeerScoreParams.decayInterval]
/// while [start]ed, and [score] computes a peer's score from them.
class PeerScore {
  final PeerScoreParams params;

  /// The score parameters of each scored topic: those of [params], changed
  /// by [setTopicScoreParams].
  final Map<String, TopicScoreParams> _topics;

  /// The score parameters of [topic], if it is scored.
  TopicScoreParams? topicScoreParams(String topic) => _topics[topic];

  /// Sets the score parameters of [topic], as go-libp2p-pubsub's
  /// `SetTopicScoreParams` (`Topic.SetScoreParams`): a topic not scored
  /// before is scored from now on. If the new parameters lower the caps of
  /// first or mesh message deliveries, the counters of the peers are capped
  /// to them. Throws an [ArgumentError] if [p] is invalid.
  void setTopicScoreParams(String topic, TopicScoreParams p) {
    p.validate();
    final old = _topics[topic];
    _topics[topic] = p;
    if (old == null) return;
    if (p.firstMessageDeliveriesCap >= old.firstMessageDeliveriesCap &&
        p.meshMessageDeliveriesCap >= old.meshMessageDeliveriesCap) {
      return;
    }
    for (final pstats in _peerStats.values) {
      final t = pstats.topics[topic];
      if (t == null) continue;
      if (t.firstMessageDeliveries > p.firstMessageDeliveriesCap) {
        t.firstMessageDeliveries = p.firstMessageDeliveriesCap;
      }
      if (t.meshMessageDeliveries > p.meshMessageDeliveriesCap) {
        t.meshMessageDeliveries = p.meshMessageDeliveriesCap;
      }
    }
  }

  /// Returns the IPs of the connections to a peer, for P6. Set by the
  /// router; IPv6 addresses also count for their /64.
  final List<String> Function(PeerId peer)? _connectionIps;

  final Map<PeerId, _PeerStats> _peerStats = {};

  /// IP -> the peers connected from it.
  final Map<String, Set<PeerId>> _peerIPs = {};

  final Map<String, _DeliveryRecord> _deliveries = {};

  /// Delivery record IDs with their expiry, oldest first.
  final Queue<(String, DateTime)> _deliveryExpiry = Queue();

  late final List<IpNet> _whitelist =
      params.ipColocationFactorWhitelist.map((c) => IpNet.tryParse(c)!).toList();

  Timer? _refreshTimer;
  Timer? _refreshIpsTimer;
  Timer? _gcTimer;

  /// Creates peer scoring with [params], which must be valid (see
  /// [PeerScoreParams.validate]). [connectionIps] returns the IP addresses
  /// of the connections to a peer.
  PeerScore(this.params, {List<String> Function(PeerId peer)? connectionIps})
      : _connectionIps = connectionIps,
        _topics = Map.of(params.topics) {
    params.validate();
  }

  /// Starts decaying counters and expiring records.
  void start() {
    stop();
    _refreshTimer = Timer.periodic(params.decayInterval, (_) => refreshScores());
    _refreshIpsTimer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshIps());
    _gcTimer = Timer.periodic(const Duration(minutes: 1), (_) => _gcDeliveryRecords());
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshIpsTimer?.cancel();
    _gcTimer?.cancel();
    _refreshTimer = _refreshIpsTimer = _gcTimer = null;
  }

  /// The score of [peer]; 0 for an unknown peer.
  double score(PeerId peer) {
    final pstats = _peerStats[peer];
    if (pstats == null) return 0;

    var score = 0.0;
    for (final entry in pstats.topics.entries) {
      final topicParams = _topics[entry.key];
      if (topicParams == null) continue; // Not a scored topic.
      final t = entry.value;
      var topicScore = 0.0;

      // P1: time in mesh.
      if (t.inMesh) {
        var p1 = (t.meshTime.inMicroseconds ~/ topicParams.timeInMeshQuantum.inMicroseconds).toDouble();
        if (p1 > topicParams.timeInMeshCap) p1 = topicParams.timeInMeshCap;
        topicScore += p1 * topicParams.timeInMeshWeight;
      }

      // P2: first message deliveries.
      topicScore += t.firstMessageDeliveries * topicParams.firstMessageDeliveriesWeight;

      // P3: mesh message delivery deficit.
      if (t.meshMessageDeliveriesActive &&
          t.meshMessageDeliveries < topicParams.meshMessageDeliveriesThreshold) {
        final deficit = topicParams.meshMessageDeliveriesThreshold - t.meshMessageDeliveries;
        topicScore += deficit * deficit * topicParams.meshMessageDeliveriesWeight;
      }

      // P3b: sticky mesh failure penalty.
      topicScore += t.meshFailurePenalty * topicParams.meshFailurePenaltyWeight;

      // P4: invalid messages.
      topicScore += t.invalidMessageDeliveries * t.invalidMessageDeliveries *
          topicParams.invalidMessageDeliveriesWeight;

      score += topicScore * topicParams.topicWeight;
    }

    if (params.topicScoreCap > 0 && score > params.topicScoreCap) {
      score = params.topicScoreCap;
    }

    // P5: application-specific score.
    score += params.appSpecificScore(peer) * params.appSpecificWeight;

    // P6: IP colocation.
    score += _ipColocationFactor(peer) * params.ipColocationFactorWeight;

    // P7: behaviour penalty.
    if (pstats.behaviourPenalty > params.behaviourPenaltyThreshold) {
      final excess = pstats.behaviourPenalty - params.behaviourPenaltyThreshold;
      score += excess * excess * params.behaviourPenaltyWeight;
    }

    return score;
  }

  /// A snapshot of the score of [peer] and its components, or null for an
  /// unknown peer.
  PeerScoreSnapshot? snapshot(PeerId peer) {
    final pstats = _peerStats[peer];
    if (pstats == null) return null;
    return PeerScoreSnapshot(score(peer), Map.unmodifiable(pstats.topics),
        params.appSpecificScore(peer), _ipColocationFactor(peer), pstats.behaviourPenalty);
  }

  double _ipColocationFactor(PeerId peer) {
    final pstats = _peerStats[peer];
    if (pstats == null) return 0;
    var result = 0.0;
    for (final ip in pstats.ips) {
      if (_whitelist.isNotEmpty) {
        final whitelisted =
            pstats.ipWhitelist.putIfAbsent(ip, () => _whitelist.any((net) => net.contains(ip)));
        if (whitelisted) continue;
      }
      final peersInIP = _peerIPs[ip]?.length ?? 0;
      if (peersInIP > params.ipColocationFactorThreshold) {
        final surplus = (peersInIP - params.ipColocationFactorThreshold).toDouble();
        result += surplus * surplus;
      }
    }
    return result;
  }

  /// Adds [count] to the behaviour penalty (P7) of [peer].
  void addPenalty(PeerId peer, int count) {
    final pstats = _peerStats[peer];
    if (pstats == null) return;
    pstats.behaviourPenalty += count;
  }

  /// Decays the counters, and deletes the scores of peers disconnected for
  /// [PeerScoreParams.retainScore]. Called every decay interval.
  void refreshScores() {
    final now = clock.now();
    final expired = <PeerId>[];
    _peerStats.forEach((peer, pstats) {
      if (!pstats.connected) {
        // Retained scores do not decay, so that reconnecting does not help.
        if (now.isAfter(pstats.expire)) expired.add(peer);
        return;
      }
      pstats.topics.forEach((topic, t) {
        final topicParams = _topics[topic];
        if (topicParams == null) return;
        t.firstMessageDeliveries = _decay(t.firstMessageDeliveries, topicParams.firstMessageDeliveriesDecay);
        t.meshMessageDeliveries = _decay(t.meshMessageDeliveries, topicParams.meshMessageDeliveriesDecay);
        t.meshFailurePenalty = _decay(t.meshFailurePenalty, topicParams.meshFailurePenaltyDecay);
        t.invalidMessageDeliveries = _decay(t.invalidMessageDeliveries, topicParams.invalidMessageDeliveriesDecay);
        if (t.inMesh) {
          t.meshTime = now.difference(t.graftTime);
          if (t.meshTime > topicParams.meshMessageDeliveriesActivation) {
            t.meshMessageDeliveriesActive = true;
          }
        }
      });
      pstats.behaviourPenalty = _decay(pstats.behaviourPenalty, params.behaviourPenaltyDecay);
    });
    for (final peer in expired) {
      _removeIps(peer, _peerStats.remove(peer)!.ips);
      _log.fine('Deleted the retained score of ${peer.toBase58()}');
    }
  }

  double _decay(double value, double decay) {
    final decayed = value * decay;
    return decayed < params.decayToZero ? 0 : decayed;
  }

  // --- Peer events ---

  /// A peer that speaks pubsub connected.
  void addPeer(PeerId peer) {
    final pstats = _peerStats.putIfAbsent(peer, _PeerStats.new);
    pstats.connected = true;
    final ips = _ipsOf(peer);
    _setIps(peer, ips, pstats.ips);
    pstats.ips = ips;
  }

  /// A peer disconnected. A score > 0 is deleted; otherwise it is kept for
  /// [PeerScoreParams.retainScore], with the first deliveries reset and the
  /// mesh delivery deficit turned into a failure penalty.
  void removePeer(PeerId peer) {
    final pstats = _peerStats[peer];
    if (pstats == null) return;
    if (score(peer) > 0) {
      _removeIps(peer, pstats.ips);
      _peerStats.remove(peer);
      return;
    }
    pstats.topics.forEach((topic, t) {
      t.firstMessageDeliveries = 0;
      final threshold = _topics[topic]?.meshMessageDeliveriesThreshold ?? 0;
      if (t.inMesh && t.meshMessageDeliveriesActive && t.meshMessageDeliveries < threshold) {
        final deficit = threshold - t.meshMessageDeliveries;
        t.meshFailurePenalty += deficit * deficit;
      }
      t.inMesh = false;
    });
    pstats.connected = false;
    pstats.expire = clock.now().add(params.retainScore);
  }

  /// [peer] joined our mesh for [topic].
  void graft(PeerId peer, String topic) {
    final t = _topicStats(peer, topic);
    if (t == null) return;
    t.inMesh = true;
    t.graftTime = clock.now();
    t.meshTime = Duration.zero;
    t.meshMessageDeliveriesActive = false;
  }

  /// [peer] left our mesh for [topic].
  void prune(PeerId peer, String topic) {
    final t = _topicStats(peer, topic);
    if (t == null) return;
    final threshold = _topics[topic]!.meshMessageDeliveriesThreshold;
    if (t.meshMessageDeliveriesActive && t.meshMessageDeliveries < threshold) {
      final deficit = threshold - t.meshMessageDeliveries;
      t.meshFailurePenalty += deficit * deficit;
    }
    t.inMesh = false;
  }

  // --- Message events ---

  /// Validation of message [msgId] begins (its signature is valid).
  void validateMessage(String msgId) => _record(msgId);

  /// Message [msgId] on [topic], first received from [from], was accepted.
  void deliverMessage(String msgId, PeerId from, String topic) {
    _markFirstMessageDelivery(from, topic);
    final rec = _record(msgId);
    if (rec.status != _DeliveryStatus.unknown) return;
    rec.status = _DeliveryStatus.valid;
    rec.validated = clock.now();
    // Credit the mesh peers that forwarded it while it was in validation.
    for (final peer in rec.peers) {
      if (peer != from) _markDuplicateMessageDelivery(peer, topic, null);
    }
  }

  /// Message [msgId] on [topic], first received from [from], was not
  /// accepted, for [reason].
  void rejectMessage(String msgId, PeerId from, String topic, RejectReason reason) {
    if (reason == RejectReason.invalidSignature) {
      // The ID may be forged: penalise the sender only, track nothing.
      _markInvalidMessageDelivery(from, topic);
      return;
    }
    final rec = _record(msgId);
    if (rec.status != _DeliveryStatus.unknown) return;
    switch (reason) {
      case RejectReason.validationThrottled:
        rec.status = _DeliveryStatus.throttled;
        rec.peers = {};
        return;
      case RejectReason.validationIgnored:
        rec.status = _DeliveryStatus.ignored;
        rec.peers = {};
        return;
      case RejectReason.validationFailed:
      case RejectReason.invalidSignature:
        break;
    }
    rec.status = _DeliveryStatus.invalid;
    _markInvalidMessageDelivery(from, topic);
    for (final peer in rec.peers) {
      _markInvalidMessageDelivery(peer, topic);
    }
    rec.peers = {};
  }

  /// [from] sent message [msgId] on [topic], which was seen before.
  void duplicateMessage(String msgId, PeerId from, String topic) {
    final rec = _record(msgId);
    if (rec.peers.contains(from)) return; // Counted already.
    switch (rec.status) {
      case _DeliveryStatus.unknown:
        // In validation: credit or penalise when it completes.
        rec.peers.add(from);
      case _DeliveryStatus.valid:
        rec.peers.add(from);
        _markDuplicateMessageDelivery(from, topic, rec.validated);
      case _DeliveryStatus.invalid:
        _markInvalidMessageDelivery(from, topic);
      case _DeliveryStatus.throttled:
      case _DeliveryStatus.ignored:
        break;
    }
  }

  _DeliveryRecord _record(String msgId) {
    final existing = _deliveries[msgId];
    if (existing != null) return existing;
    final now = clock.now();
    final rec = _DeliveryRecord(now);
    _deliveries[msgId] = rec;
    _deliveryExpiry.addLast((msgId, now.add(params.seenMsgTTL)));
    return rec;
  }

  void _gcDeliveryRecords() {
    final now = clock.now();
    while (_deliveryExpiry.isNotEmpty && now.isAfter(_deliveryExpiry.first.$2)) {
      _deliveries.remove(_deliveryExpiry.removeFirst().$1);
    }
  }

  /// The stats of [peer] in [topic], created if [topic] is scored; null if
  /// the peer is unknown or the topic is not scored.
  TopicScoreStats? _topicStats(PeerId peer, String topic) {
    final pstats = _peerStats[peer];
    if (pstats == null) return null;
    final existing = pstats.topics[topic];
    if (existing != null) return existing;
    if (!_topics.containsKey(topic)) return null;
    return pstats.topics[topic] = TopicScoreStats();
  }

  void _markInvalidMessageDelivery(PeerId peer, String topic) {
    final t = _topicStats(peer, topic);
    if (t != null) t.invalidMessageDeliveries += 1;
  }

  void _markFirstMessageDelivery(PeerId peer, String topic) {
    final t = _topicStats(peer, topic);
    if (t == null) return;
    final topicParams = _topics[topic]!;
    t.firstMessageDeliveries += 1;
    if (t.firstMessageDeliveries > topicParams.firstMessageDeliveriesCap) {
      t.firstMessageDeliveries = topicParams.firstMessageDeliveriesCap;
    }
    if (!t.inMesh) return;
    t.meshMessageDeliveries += 1;
    if (t.meshMessageDeliveries > topicParams.meshMessageDeliveriesCap) {
      t.meshMessageDeliveries = topicParams.meshMessageDeliveriesCap;
    }
  }

  /// Credits a mesh peer for a copy received within the delivery window of
  /// the first copy ([validated] null: before validation completed).
  void _markDuplicateMessageDelivery(PeerId peer, String topic, DateTime? validated) {
    final t = _topicStats(peer, topic);
    if (t == null || !t.inMesh) return;
    final topicParams = _topics[topic]!;
    if (validated != null &&
        clock.now().difference(validated) > topicParams.meshMessageDeliveriesWindow) {
      return;
    }
    t.meshMessageDeliveries += 1;
    if (t.meshMessageDeliveries > topicParams.meshMessageDeliveriesCap) {
      t.meshMessageDeliveries = topicParams.meshMessageDeliveriesCap;
    }
  }

  // --- IP tracking ---

  List<String> _ipsOf(PeerId peer) {
    final ips = <String>[];
    for (final ip in _connectionIps?.call(peer) ?? const <String>[]) {
      final address = InternetAddress.tryParse(ip);
      if (address == null || address.isLoopback) continue; // Loopback: tests.
      ips.add(address.address);
      if (address.type == InternetAddressType.IPv6) {
        // An IPv6 peer also counts for its /64.
        final raw = Uint8List.fromList(address.rawAddress)..fillRange(8, 16, 0);
        ips.add(InternetAddress.fromRawAddress(raw, type: InternetAddressType.IPv6).address);
      }
    }
    return ips;
  }

  void _refreshIps() {
    _peerStats.forEach((peer, pstats) {
      if (!pstats.connected) return;
      final ips = _ipsOf(peer);
      _setIps(peer, ips, pstats.ips);
      pstats.ips = ips;
    });
  }

  void _setIps(PeerId peer, List<String> newIps, List<String> oldIps) {
    for (final ip in newIps) {
      if (!oldIps.contains(ip)) _peerIPs.putIfAbsent(ip, () => {}).add(peer);
    }
    _removeIps(peer, oldIps.where((ip) => !newIps.contains(ip)));
  }

  void _removeIps(PeerId peer, Iterable<String> ips) {
    for (final ip in ips) {
      final peers = _peerIPs[ip];
      if (peers == null) continue;
      peers.remove(peer);
      if (peers.isEmpty) _peerIPs.remove(ip);
    }
  }
}

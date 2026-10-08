import 'dart:async';
import 'dart:math';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import '../core/router.dart';
import '../util/timecache.dart';
import 'score_params.dart';

final _log = Logger('PeerGater');

/// The parameters of the peer gater, as go-libp2p-pubsub's
/// `PeerGaterParams`, with its defaults.
class PeerGaterParams {
  /// The ratio of throttled validations to validations above which peers
  /// are gated. Must be above 0.
  final double threshold;

  /// The decay of the global counters of validations and throttles, per
  /// [decayInterval]. Between 0 and 1.
  final double globalDecay;

  /// The decay of the counters of each IP address, per [decayInterval].
  /// Between 0 and 1.
  final double sourceDecay;

  /// How often the counters decay. At least 1 second.
  final Duration decayInterval;

  /// A counter that decays below this value is set to 0. Between 0 and 1.
  final double decayToZero;

  /// How long the counters of an IP address are kept after its last peer
  /// disconnects.
  final Duration retainStats;

  /// How long after the last throttled validation peers are gated. At least
  /// 1 second.
  final Duration quiet;

  /// The weight of a duplicate message in a peer's counters. Above 0.
  final double duplicateWeight;

  /// The weight of an ignored message. At least 1.
  final double ignoreWeight;

  /// The weight of a rejected message. At least 1.
  final double rejectWeight;

  /// The weight of a delivered message on each topic; 1 for topics not
  /// listed.
  final Map<String, double> topicDeliveryWeights;

  PeerGaterParams({
    this.threshold = 0.33,
    double? globalDecay,
    double? sourceDecay,
    this.decayInterval = const Duration(seconds: 1),
    this.decayToZero = 0.01,
    this.retainStats = const Duration(hours: 6),
    this.quiet = const Duration(minutes: 1),
    this.duplicateWeight = 0.125,
    this.ignoreWeight = 1.0,
    this.rejectWeight = 16.0,
    this.topicDeliveryWeights = const {},
  })  : globalDecay = globalDecay ?? scoreParameterDecay(const Duration(minutes: 2)),
        sourceDecay = sourceDecay ?? scoreParameterDecay(const Duration(hours: 1));

  /// Throws an [ArgumentError] if a parameter is out of range, as Go's
  /// `validate`.
  void validate() {
    void check(bool ok, String name, String rule) {
      if (!ok) throw ArgumentError('invalid $name; $rule');
    }

    check(threshold > 0, 'threshold', 'must be > 0');
    check(globalDecay > 0 && globalDecay < 1, 'globalDecay', 'must be between 0 and 1');
    check(sourceDecay > 0 && sourceDecay < 1, 'sourceDecay', 'must be between 0 and 1');
    check(decayInterval >= const Duration(seconds: 1), 'decayInterval', 'must be at least 1s');
    check(decayToZero > 0 && decayToZero < 1, 'decayToZero', 'must be between 0 and 1');
    check(quiet >= const Duration(seconds: 1), 'quiet', 'must be at least 1s');
    check(duplicateWeight > 0, 'duplicateWeight', 'must be > 0');
    check(ignoreWeight >= 1, 'ignoreWeight', 'must be >= 1');
    check(rejectWeight >= 1, 'rejectWeight', 'must be >= 1');
  }
}

/// The counters of an IP address.
class _Stats {
  int connected = 0;
  Duration expire = Duration.zero;
  double deliver = 0, duplicate = 0, ignore = 0, reject = 0;
}

/// The peer gater, as go-libp2p-pubsub's `peerGater` (`WithPeerGater`): when
/// validation is being throttled, it handles only the control messages of
/// some peers, chosen at random, the more likely the fewer of their
/// messages were delivered. Counters are kept per IP address, so that
/// peers cannot reset them by changing their peer ID.
class PeerGater {
  final PeerGaterParams params;
  final Host _host;
  final Random _random;
  final MonotonicClock _clock;

  double _validate = 0, _throttle = 0;
  Duration? _lastThrottle;
  final Map<PeerId, _Stats> _peerStats = {};
  final Map<String, _Stats> _ipStats = {};
  Timer? _decayTimer;

  /// The IP address of a peer; by default that of its connection.
  final String Function(PeerId peer)? getIP;

  PeerGater(this.params, this._host, {Random? random, MonotonicClock? clock, this.getIP})
      : _random = random ?? Random(),
        _clock = clock ?? monotonicNow {
    params.validate();
  }

  void start() {
    _decayTimer ??= Timer.periodic(params.decayInterval, (_) => decay());
  }

  void stop() {
    _decayTimer?.cancel();
    _decayTimer = null;
  }

  /// Decays the counters, and forgets the IP addresses without peers whose
  /// counters have expired.
  void decay() {
    double decayed(double v, double decay) {
      v *= decay;
      return v < params.decayToZero ? 0 : v;
    }

    _validate = decayed(_validate, params.globalDecay);
    _throttle = decayed(_throttle, params.globalDecay);
    final now = _clock();
    _ipStats.removeWhere((ip, st) {
      if (st.connected > 0) {
        st
          ..deliver = decayed(st.deliver, params.sourceDecay)
          ..duplicate = decayed(st.duplicate, params.sourceDecay)
          ..ignore = decayed(st.ignore, params.sourceDecay)
          ..reject = decayed(st.reject, params.sourceDecay);
        return false;
      }
      return st.expire < now;
    });
  }

  _Stats _stats(PeerId peer) => _peerStats.putIfAbsent(peer, () => _ipStats.putIfAbsent(_ipOf(peer), _Stats.new));

  String _ipOf(PeerId peer) {
    final getIP = this.getIP;
    if (getIP != null) return getIP(peer);
    // Go picks the connection with the most streams; dart_libp2p lists
    // streams asynchronously, so the first unlimited connection is used.
    final conns = _host.network.connsToPeer(peer);
    if (conns.isEmpty) return '<unknown>';
    final conn = conns.firstWhere((c) => !c.stat.stats.limited, orElse: () => conns.first);
    final ip = conn.remoteMultiaddr.ip;
    if (ip == null) {
      _log.fine('Cannot determine the IP address of ${peer.toBase58()} from ${conn.remoteMultiaddr}');
      return '<unknown>';
    }
    return ip;
  }

  /// Which RPCs of [peer] to handle: all of them, unless validation was
  /// throttled within [PeerGaterParams.quiet] at a rate above the
  /// threshold. Then only its control messages, with a probability that
  /// falls as its share of delivered messages falls.
  AcceptStatus acceptFrom(PeerId peer) {
    final last = _lastThrottle;
    if (last == null || _clock() - last > params.quiet) return AcceptStatus.all;
    if (_throttle == 0) return AcceptStatus.all;
    if (_validate != 0 && _throttle / _validate < params.threshold) return AcceptStatus.all;

    final st = _stats(peer);
    final total = st.deliver +
        params.duplicateWeight * st.duplicate +
        params.ignoreWeight * st.ignore +
        params.rejectWeight * st.reject;
    if (total == 0) return AcceptStatus.all;
    final threshold = (1 + st.deliver) / (1 + total);
    if (_random.nextDouble() < threshold) return AcceptStatus.all;
    _log.fine('Throttling peer ${peer.toBase58()} (threshold $threshold)');
    return AcceptStatus.control;
  }

  /// Whether the gater holds counters for [peer], a connected peer.
  bool tracksPeer(PeerId peer) => _peerStats.containsKey(peer);

  /// Whether the gater holds counters for the IP address [ip].
  bool tracksIp(String ip) => _ipStats.containsKey(ip);

  void addPeer(PeerId peer) => _stats(peer).connected++;

  void removePeer(PeerId peer) {
    final st = _stats(peer);
    st
      ..connected -= 1
      ..expire = _clock() + params.retainStats;
    _peerStats.remove(peer);
  }

  /// A message from a peer entered validation.
  void validateMessage() => _validate++;

  void deliverMessage(PeerId from, String topic) {
    final weight = params.topicDeliveryWeights[topic] ?? 0;
    _stats(from).deliver += weight == 0 ? 1 : weight;
  }

  void duplicateMessage(PeerId from) => _stats(from).duplicate++;

  /// A message from [from] was not delivered, for [reason] (one of PubSub's
  /// rejection reasons).
  void rejectMessage(PeerId from, String reason) {
    switch (reason) {
      case 'validation queue full':
      case 'validation throttled':
        _lastThrottle = _clock();
        _throttle++;
      case 'validation ignored':
      case 'validation timeout':
        _stats(from).ignore++;
      default:
        _stats(from).reject++;
    }
  }
}

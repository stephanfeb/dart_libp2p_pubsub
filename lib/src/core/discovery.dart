import 'dart:async';
import 'dart:math';

import 'package:dart_libp2p/core/discovery.dart';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/p2p/discovery/backoff/backoff.dart';
import 'package:dart_libp2p/p2p/discovery/backoff/backoff_connector.dart';
import 'package:logging/logging.dart';

import 'router.dart';

final _log = Logger('PubSubDiscovery');

/// The prefix of the discovery namespace of a topic, as go-libp2p-pubsub's:
/// a topic is advertised and looked up as `floodsub:<topic>`, whatever the
/// router.
const String discoveryNamespacePrefix = 'floodsub:';

/// How often discovery checks the subscribed topics for peers (Go's
/// `DiscoveryPollInterval`).
const Duration discoveryPollInterval = Duration(seconds: 1);

/// How long to wait before advertising again after an advertisement fails
/// (Go's `discoveryAdvertiseRetryInterval`).
const Duration discoveryAdvertiseRetryInterval = Duration(minutes: 2);

/// How long one search for the peers of a topic lasts (Go: 10 s).
const Duration discoveryFindPeersTimeout = Duration(seconds: 10);

/// Creates the connector that dials the peers discovery finds.
typedef DiscoveryConnectorFactory = BackoffConnector Function(Host host);

/// go-libp2p-pubsub's default connector: an exponential backoff of 10 s to
/// 1 hour between attempts at a peer, for up to 100 peers, and dials of up to
/// 2 minutes.
BackoffConnector defaultDiscoveryConnector(Host host) => BackoffConnector(
      host,
      100,
      const Duration(minutes: 2),
      newExponentialBackoff(const Duration(seconds: 10), const Duration(hours: 1), fullJitter,
          const Duration(seconds: 1), 5.0, Duration.zero, Random()),
    );

/// The discovery pipeline of PubSub, as go-libp2p-pubsub's `discover`:
/// advertises the topics the node subscribes to, looks for peers of the
/// subscribed topics that the router has not enough peers on, and connects
/// to the peers it finds.
class PubSubDiscovery {
  final Discovery _discovery;
  final List<DiscoveryOption> _options;
  final DiscoveryConnectorFactory _connectorFactory;

  BackoffConnector? _connector;
  Router? _router;
  Iterable<String> Function()? _topics;
  Timer? _poll;
  bool _running = false;

  /// The advertisement of each topic advertised.
  final Map<String, _Advertisement> _advertising = {};

  /// The search under way for each topic.
  final Map<String, Future<void>> _ongoing = {};

  /// Discovers peers with [discovery], passing it [options] on each call.
  /// The peers found are dialed by the connector [connector] creates, by
  /// default [defaultDiscoveryConnector].
  PubSubDiscovery(Discovery discovery,
      {List<DiscoveryOption> options = const [], DiscoveryConnectorFactory? connector})
      : _discovery = discovery,
        _options = options,
        _connectorFactory = connector ?? defaultDiscoveryConnector;

  /// Starts polling: every [discoveryPollInterval], each of [topics] on
  /// which [router] has not enough peers is searched.
  void start(Host host, Router router, Iterable<String> Function() topics) {
    if (_running) return;
    _running = true;
    _connector ??= _connectorFactory(host);
    _router = router;
    _topics = topics;
    _requestDiscovery();
    _poll = Timer.periodic(discoveryPollInterval, (_) => _requestDiscovery());
  }

  /// Stops polling and advertising. Searches under way end within
  /// [discoveryFindPeersTimeout].
  void stop() {
    _running = false;
    _poll?.cancel();
    _poll = null;
    for (final ad in _advertising.values) {
      ad.cancel();
    }
    _advertising.clear();
  }

  void _requestDiscovery() {
    final router = _router;
    if (router == null) return;
    for (final topic in _topics!()) {
      if (!router.enoughPeers(topic, 0)) discover(topic);
    }
  }

  /// Searches for peers of [topic] and dials them, unless a search for the
  /// topic is under way. Completes when the search ends.
  Future<void> discover(String topic) {
    if (!_running) return Future.value();
    // The callback must not return the removed future, which whenComplete
    // would wait for: itself.
    return _ongoing[topic] ??= _handleDiscovery(topic).whenComplete(() {
      _ongoing.remove(topic);
    });
  }

  Future<void> _handleDiscovery(String topic) async {
    final Stream<AddrInfo> found;
    try {
      found = await _discovery
          .findPeers('$discoveryNamespacePrefix$topic', _options)
          .timeout(discoveryFindPeersTimeout);
    } catch (e) {
      _log.fine('Error finding peers for topic $topic: $e');
      return;
    }
    // As go-libp2p-pubsub, the search lasts at most 10 s.
    final bounded = StreamController<AddrInfo>();
    void close() {
      if (!bounded.isClosed) bounded.close();
    }
    final subscription = found.listen(bounded.add, onError: (Object e) {
      _log.fine('Error finding peers for topic $topic: $e');
    }, onDone: close);
    final timer = Timer(discoveryFindPeersTimeout, () {
      subscription.cancel();
      close();
    });
    try {
      await _connector!.connect(bounded.stream);
    } finally {
      timer.cancel();
      await subscription.cancel();
      close();
    }
  }

  /// Advertises [topic], again when the advertisement expires, until
  /// [stopAdvertise] or [stop]. Does nothing if [topic] is advertised.
  void advertise(String topic) {
    if (!_running || _advertising.containsKey(topic)) return;
    final ad = _Advertisement();
    _advertising[topic] = ad;
    _advertise(topic, ad);
  }

  Future<void> _advertise(String topic, _Advertisement ad) async {
    var next = Duration.zero;
    try {
      next = await _discovery.advertise('$discoveryNamespacePrefix$topic', _options);
    } catch (e) {
      _log.warning('Error advertising topic $topic: $e');
    }
    if (next <= Duration.zero) next = discoveryAdvertiseRetryInterval;
    if (ad.cancelled) return;
    ad.timer = Timer(next, () => _advertise(topic, ad));
  }

  /// Stops advertising [topic].
  void stopAdvertise(String topic) => _advertising.remove(topic)?.cancel();
}

class _Advertisement {
  bool cancelled = false;
  Timer? timer;

  void cancel() {
    cancelled = true;
    timer?.cancel();
  }
}

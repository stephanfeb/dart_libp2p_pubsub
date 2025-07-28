import 'dart:async';

// Assuming Discovery, AddrInfo, PeerId are from dart_libp2p package
// and DiscoveryOption might be part of it or defined elsewhere if needed.
// For now, assuming DiscoveryOption is not strictly needed for basic advertise/findPeers.
import 'package:dart_libp2p/core/discovery.dart'; // For Discovery interface
import 'package:dart_libp2p/core/peer/addr_info.dart'; // For AddrInfo
import 'package:dart_libp2p/core/peer/peer_id.dart';   // For PeerId

// Callback for when a new peer relevant to PubSub is discovered.
typedef PubSubPeerDiscoveredCallback = void Function(PeerId peerId, String? context); // Added context

/// A default service tag for general PubSub node discovery.
const String DEFAULT_GENERAL_PUBSUB_SERVICE_TAG = "/libp2p/pubsub/gossipsub/1.1.0/discovery";

/// Prefix for creating discovery namespaces for specific topics.
const String TOPIC_DISCOVERY_PREFIX = "gossipsub_topic:";

/// Handles PubSub-specific peer discovery aspects by leveraging a libp2p Discovery service.
class PubSubDiscovery {
  final Discovery _discoveryService;
  final String? generalServiceTag;

  final List<PubSubPeerDiscoveredCallback> _discoveryCallbacks = [];
  
  StreamSubscription<AddrInfo>? _generalServiceSubscription;
  final Map<String, StreamSubscription<AddrInfo>> _topicPeerSubscriptions = {};
  // We might need to manage advertisement TTLs and re-advertise, but that's for future enhancement.
  // final Map<String, Timer> _advertisementTimers = {}; // For re-advertising

  /// Creates a PubSubDiscovery instance.
  ///
  /// [_discoveryService]: The underlying libp2p Discovery service (e.g., IpfsDHT).
  /// [generalServiceTag]: An optional namespace string for general PubSub service
  /// advertisement. If null, `DEFAULT_GENERAL_PUBSUB_SERVICE_TAG` can be used by the caller
  /// or general advertisement can be skipped.
  PubSubDiscovery(this._discoveryService, {this.generalServiceTag});

  /// Starts general PubSub service discovery and advertisement if [generalServiceTag] is configured.
  Future<void> start() async {
    if (generalServiceTag != null && generalServiceTag!.isNotEmpty) {
      try {
        print('PubSubDiscovery: Advertising general service tag: $generalServiceTag');
        // Advertise returns a Future<Duration> (TTL). We might need to re-advertise.
        await _discoveryService.advertise(generalServiceTag!);
        // TODO: Handle re-advertisement based on TTL.

        print('PubSubDiscovery: Finding peers for general service tag: $generalServiceTag');
        final stream = await _discoveryService.findPeers(generalServiceTag!);
        _generalServiceSubscription?.cancel(); // Cancel previous if any
        _generalServiceSubscription = stream.listen(
          (addrInfo) => _handleDiscoveredPeer(addrInfo, generalServiceTag),
          onError: (e) => print('PubSubDiscovery: Error in general service peer stream: $e'),
          onDone: () => print('PubSubDiscovery: General service peer stream closed.'),
        );
      } catch (e, s) {
        print('PubSubDiscovery: Error during general service start: $e\nStack trace:\n$s');
      }
    }
  }

  /// Starts finding peers for a specific topic and advertises interest in it.
  Future<void> discoverTopic(String topic) async {
    final topicNamespace = "$TOPIC_DISCOVERY_PREFIX$topic";
    try {
      print('PubSubDiscovery: Advertising topic: $topicNamespace');
      await _discoveryService.advertise(topicNamespace);
      // TODO: Handle re-advertisement for topic.

      print('PubSubDiscovery: Finding peers for topic: $topicNamespace');
      final stream = await _discoveryService.findPeers(topicNamespace);
      
      // Cancel any existing subscription for this topic before starting a new one.
      await _topicPeerSubscriptions[topicNamespace]?.cancel();
      
      _topicPeerSubscriptions[topicNamespace] = stream.listen(
        (addrInfo) => _handleDiscoveredPeer(addrInfo, topicNamespace),
        onError: (e) => print('PubSubDiscovery: Error in topic peer stream for $topicNamespace: $e'),
        onDone: () {
          print('PubSubDiscovery: Topic peer stream for $topicNamespace closed.');
          _topicPeerSubscriptions.remove(topicNamespace);
        },
      );
    } catch (e, s) {
      print('PubSubDiscovery: Error during topic discovery for $topicNamespace: $e\nStack trace:\n$s');
    }
  }

  /// Stops finding peers for a specific topic.
  /// Note: This currently only stops listening for new peers. It does not "unadvertise".
  Future<void> stopDiscoveringTopic(String topic) async {
    final topicNamespace = "$TOPIC_DISCOVERY_PREFIX$topic";
    final subscription = _topicPeerSubscriptions.remove(topicNamespace);
    if (subscription != null) {
      await subscription.cancel();
      print('PubSubDiscovery: Stopped discovering peers for topic: $topicNamespace');
    }
    // TODO: Implement unadvertising if the Discovery service supports it or manage advertisement TTLs.
  }

  void _handleDiscoveredPeer(AddrInfo addrInfo, String? discoveryContext) {
    print('PubSubDiscovery: Discovered peer ${addrInfo.id.toBase58()} (context: $discoveryContext) with addrs: ${addrInfo.addrs}');
    for (final callback in List<PubSubPeerDiscoveredCallback>.from(_discoveryCallbacks)) {
      try {
        callback(addrInfo.id, discoveryContext);
      } catch (e, s) {
        print('PubSubDiscovery: Error in discovery callback: $e\nStack trace:\n$s');
      }
    }
  }

  /// Registers a callback to be invoked when a new PubSub peer is discovered.
  void addDiscoveryListener(PubSubPeerDiscoveredCallback callback) {
    if (!_discoveryCallbacks.contains(callback)) {
      _discoveryCallbacks.add(callback);
    }
  }

  /// Unregisters a previously registered discovery callback.
  void removeDiscoveryListener(PubSubPeerDiscoveredCallback callback) {
    _discoveryCallbacks.remove(callback);
  }

  /// Cleans up resources, cancelling all active discovery operations.
  Future<void> dispose() async {
    print('PubSubDiscovery: Disposing...');
    await _generalServiceSubscription?.cancel();
    _generalServiceSubscription = null;

    for (final subscription in _topicPeerSubscriptions.values) {
      await subscription.cancel();
    }
    _topicPeerSubscriptions.clear();
    _discoveryCallbacks.clear();
    // TODO: Cancel any re-advertisement timers if implemented.
    print('PubSubDiscovery: Disposed.');
  }
}

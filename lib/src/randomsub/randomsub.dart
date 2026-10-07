import 'dart:math';

import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../core/comm.dart';
import '../floodsub/floodsub.dart';

/// The minimum number of peers RandomSub sends a message to
/// (go-libp2p-pubsub's `RandomSubD`).
const int randomSubD = 6;

/// The RandomSub router, as go-libp2p-pubsub's `RandomSubRouter`: a message
/// goes to all FloodSub peers of its topic and to a random subset of the
/// RandomSub peers, of `max(RandomSubD, sqrt(networkSize))` peers.
class RandomSubRouter extends FloodSubRouter {
  /// The estimated size of the network.
  final int networkSize;
  final Random _random;

  RandomSubRouter({required this.networkSize, Random? random, super.seenMessagesTTL})
      : _random = random ?? Random();

  @override
  List<String> get protocols => const [randomSubID, floodSubID];

  @override
  Iterable<PeerId> selectPeers(String topic, List<PeerId> candidates) {
    final flood = candidates.where((p) => peerProtocols[p] == floodSubID).toList();
    final random = candidates.where((p) => peerProtocols[p] != floodSubID).toList();
    if (random.length > randomSubD) {
      final target = min(max(randomSubD, sqrt(networkSize).ceil()), random.length);
      random.shuffle(_random);
      return [...flood, ...random.take(target)];
    }
    return [...flood, ...random];
  }
}

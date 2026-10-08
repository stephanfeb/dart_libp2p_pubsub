import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import '../core/comm.dart';
import '../core/message.dart';
import '../core/pubsub.dart';
import '../core/router.dart';
import '../core/topic.dart';
import '../gossipsub/rpc_queue.dart';
import '../pb/rpc.pb.dart' as pb;
import '../util/midgen.dart';
import '../util/timecache.dart';

final _log = Logger('FloodSubRouter');

/// The number of peers FloodSub wants on a topic before discovery stops
/// looking for more (go-libp2p-pubsub's `FloodSubTopicSearchSize`).
const int floodSubTopicSearchSize = 5;

/// The FloodSub router, as go-libp2p-pubsub's `FloodSubRouter`: every
/// message goes to every connected peer subscribed to its topic, except the
/// peer it came from and its author.
///
/// Subclasses choose other recipients by overriding [selectPeers].
class FloodSubRouter implements Router {
  PubSub? _pubsub;
  RpcOutgoingQueueManager? _queue;

  /// How long the ID of a seen message is remembered.
  final Duration seenMessagesTTL;
  late final FirstSeenCache<String> _seen = FirstSeenCache<String>(seenMessagesTTL, 1 << 17);

  /// The pubsub protocol of each peer added.
  final Map<PeerId, String> peerProtocols = {};

  /// The topics each peer is subscribed to.
  final Map<PeerId, Set<String>> _peerTopics = {};

  FloodSubRouter({this.seenMessagesTTL = const Duration(minutes: 2)});

  @override
  List<String> get protocols => const [floodSubID];

  PubSub? get pubsub => _pubsub;

  @override
  Future<void> attach(PubSub pubsub) async {
    _pubsub = pubsub;
    _queue = RpcOutgoingQueueManager(pubsub.comms, protocols.first);
  }

  @override
  Future<void> detach() async {
    _queue?.clearAll();
    _pubsub = null;
  }

  @override
  Future<void> addPeer(PeerId peerId, String protocolId) async {
    peerProtocols[peerId] = protocolId;
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    _pubsub?.removePeer(peerId);
    peerProtocols.remove(peerId);
    _peerTopics.remove(peerId);
    _queue?.peerDisconnected(peerId);
  }

  @override
  AcceptStatus acceptFrom(PeerId peer) => AcceptStatus.all;

  @override
  Future<Set<String>> handleRpc(PeerId peerId, pb.RPC rpc) async {
    // Subscriptions first, synchronously (see Router.handleRpc).
    for (final sub in rpc.subscriptions) {
      if (sub.subscribe) {
        _peerTopics.putIfAbsent(peerId, () => {}).add(sub.topicid);
      } else {
        _peerTopics[peerId]?.remove(sub.topicid);
      }
    }
    final pending = <Future<String?>>[];
    for (final msg in rpc.publish) {
      final id = _idOf(msg);
      if (_seen.contains(id)) continue;
      pending.add(_validateAndForward(peerId, msg, id));
    }
    return {for (final id in await Future.wait(pending)) if (id != null) id};
  }

  Future<String?> _validateAndForward(PeerId from, pb.Message msg, String id) async {
    final pubsub = _pubsub;
    if (pubsub == null) return null;
    var duplicate = false;
    final result = await pubsub.validateMessage(PubSubMessage(rpcMessage: msg, receivedFrom: from),
        markSeen: () {
      if (_seen.contains(id)) {
        duplicate = true;
        return false;
      }
      _seen.add(id);
      return true;
    });
    if (duplicate || result != ValidationResult.accept || _pubsub == null) return null;
    _seen.add(id);
    _send(msg, from);
    return id;
  }

  @override
  Future<void> publish(PubSubMessage message) async {
    final pubsub = _pubsub;
    if (pubsub == null) return;
    _seen.add(_idOf(message.rpcMessage));
    _send(message.rpcMessage, message.receivedFrom ?? pubsub.host.id);
  }

  void _send(pb.Message msg, PeerId from) {
    final author = _authorOf(msg);
    final candidates = topicPeers(msg.topic).where((p) => p != from && p != author).toList();
    final rpc = pb.RPC()..publish.add(msg);
    for (final peerId in selectPeers(msg.topic, candidates)) {
      _queue?.sendRpc(peerId, rpc);
    }
  }

  /// The number of peers [enoughPeers] wants on a topic by default
  /// (go-libp2p-pubsub's `FloodSubTopicSearchSize`).
  int get topicSearchSize => floodSubTopicSearchSize;

  /// As go-libp2p-pubsub: enough when [suggested] peers, or
  /// [topicSearchSize] if 0, are subscribed to [topic].
  @override
  bool enoughPeers(String topic, int suggested) =>
      topicPeers(topic).length >= (suggested == 0 ? topicSearchSize : suggested);

  /// The recipients of a message on [topic] among [candidates]: all of them.
  Iterable<PeerId> selectPeers(String topic, List<PeerId> candidates) => candidates;

  /// The connected peers subscribed to [topic].
  List<PeerId> topicPeers(String topic) {
    final connected = _pubsub?.host.network.peers.toSet() ?? const <PeerId>{};
    return [
      for (final entry in _peerTopics.entries)
        if (entry.value.contains(topic) && connected.contains(entry.key)) entry.key,
    ];
  }

  String _idOf(pb.Message msg) => (_pubsub?.messageIdFn ?? defaultMessageIdFn)(msg);

  PeerId? _authorOf(pb.Message msg) {
    if (msg.from.isEmpty) return null;
    try {
      return PeerId.fromBytes(Uint8List.fromList(msg.from));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> join(Topic topic) async {}

  @override
  Future<void> leave(Topic topic) async {}

  @override
  Future<void> start() async {
    _log.fine('FloodSubRouter started.');
  }

  @override
  Future<void> stop() async {
    for (final peerId in {...peerProtocols.keys, ..._peerTopics.keys}) {
      await removePeer(peerId);
    }
    _seen.clear();
  }
}

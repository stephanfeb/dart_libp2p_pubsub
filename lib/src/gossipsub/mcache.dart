import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../pb/rpc.pb.dart' as pb;

/// The default number of history windows (go-libp2p-pubsub's
/// `GossipSubHistoryLength`).
const int defaultMessageCacheHistoryLength = 5;

/// The default number of recent windows gossiped about (go-libp2p-pubsub's
/// `GossipSubHistoryGossip`).
const int defaultMessageCacheHistoryGossip = 3;

class _CacheEntry {
  final String id;
  final String topic;
  _CacheEntry(this.id, this.topic);
}

/// The message cache of GossipSub, as go-libp2p-pubsub's `MessageCache`.
///
/// It keeps the messages of the last [historyLength] heartbeats, to answer
/// IWANTs, in sliding windows; the heartbeat calls [shift] to open a new
/// window and drop the messages of the oldest. IHAVE gossip advertises the
/// messages of the last [historyGossip] windows ([getGossipIds]).
class MessageCache {
  final int historyLength;
  final int historyGossip;

  final Map<String, pb.Message> _messages = {};

  /// How many times each peer has requested each message with IWANT.
  final Map<String, Map<PeerId, int>> _peerTx = {};

  /// The windows, newest first.
  final List<List<_CacheEntry>> _history;

  MessageCache({
    this.historyLength = defaultMessageCacheHistoryLength,
    this.historyGossip = defaultMessageCacheHistoryGossip,
  }) : _history = List.generate(historyLength, (_) => <_CacheEntry>[]) {
    if (historyGossip > historyLength) {
      throw ArgumentError('gossip windows ($historyGossip) cannot be more than history windows ($historyLength)');
    }
  }

  /// Adds message [message], whose ID is [messageId], to the current window.
  void put(String messageId, pb.Message message) {
    _messages[messageId] = message;
    _history[0].add(_CacheEntry(messageId, message.topic));
  }

  /// The message with ID [messageId], if it is in the cache.
  pb.Message? getMessage(String messageId) => _messages[messageId];

  /// Whether the message with ID [messageId] is in the cache.
  bool seen(String messageId) => _messages.containsKey(messageId);

  /// Retrieves a message for an IWANT request from [peer], and counts the
  /// request, as go-libp2p-pubsub's `MessageCache.GetForPeer`. Returns the
  /// message and how many times [peer] has requested it, this time included,
  /// or null if the message is not in the cache.
  (pb.Message, int)? getForPeer(String messageId, PeerId peer) {
    final message = _messages[messageId];
    if (message == null) return null;
    final counts = _peerTx.putIfAbsent(messageId, () => {});
    final count = (counts[peer] ?? 0) + 1;
    counts[peer] = count;
    return (message, count);
  }

  /// The IDs of the messages on [topic] in the last [historyGossip] windows,
  /// to advertise in IHAVE gossip.
  List<String> getGossipIds(String topic) => [
        for (final window in _history.take(historyGossip))
          for (final entry in window)
            if (entry.topic == topic) entry.id,
      ];

  /// Opens a new window, dropping the messages of the oldest.
  void shift() {
    for (final entry in _history.removeLast()) {
      _messages.remove(entry.id);
      _peerTx.remove(entry.id);
    }
    _history.insert(0, <_CacheEntry>[]);
  }
}

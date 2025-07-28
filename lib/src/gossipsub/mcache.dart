import 'dart:async'; // For Timer
import 'dart:collection'; // For LinkedHashMap
import 'dart:typed_data'; // For Uint8List in getMessageId

import '../pb/rpc.pb.dart' as pb; // For pb.Message
import '../util/midgen.dart'; // For defaultMessageIdFn

// Default configuration for the message cache.
// These could be made configurable via GossipSubParams or similar.
const int defaultMessageCacheSize = 128; // Max number of messages (or message IDs) in the history window.
const int defaultMessageCacheHistoryLength = 5; // Number of gossip history windows to keep (e.g., 5 windows of 1 second each).
const Duration defaultMessageCacheGossipInterval = Duration(seconds: 1); // Interval for gossip history window shifts.

/// Represents an entry in the MessageCache, typically just the message itself
/// or a lightweight wrapper if more metadata per message (like arrival time) is needed
/// beyond what's in the history windows.
/// For this mcache, we're primarily concerned with message IDs in history windows.
/// The actual messages for IWANT are stored for a shorter TTL.

class MessageCacheWindowEntry {
  final String messageId;
  // final pb.Message message; // Optionally store the full message if needed for IWANT right away
  final DateTime receivedAt;

  MessageCacheWindowEntry(this.messageId, /*this.message,*/ this.receivedAt);
}

/// MessageCache implements a history window for recently seen messages.
/// This is used to track messages within the last few gossip propagation intervals (heartbeats)
/// to implement the IHAVE/IWANT message repair mechanism and to prevent processing duplicates.
/// It also stores full messages for a shorter period to satisfy IWANT requests.
class MessageCache {
  /// History windows: a list of sets of message IDs. Each set represents one gossip interval.
  final List<Set<String>> _history = [];
  final int _historyLength; // How many gossip intervals to keep in history (e.g., 5)

  /// Stores full messages for a short TTL to satisfy IWANT requests.
  /// messageId -> pb.Message
  final LinkedHashMap<String, pb.Message> _messages = LinkedHashMap();
  final int _messageStoreMaxSize; // Max full messages to keep (e.g., defaultMessageCacheSize)
  final Duration _messageStoreTTL;   // TTL for full messages

  // Timer for shifting history windows
  Timer? _shiftTimer;
  final Duration _gossipInterval;

  MessageCache({
    int historyLength = defaultMessageCacheHistoryLength,
    Duration gossipInterval = defaultMessageCacheGossipInterval,
    int messageStoreMaxSize = defaultMessageCacheSize,
    Duration messageStoreTTL = const Duration(seconds: 120), // e.g., 2 minutes for full messages
  })  : _historyLength = historyLength,
        _gossipInterval = gossipInterval,
        _messageStoreMaxSize = messageStoreMaxSize,
        _messageStoreTTL = messageStoreTTL {
    for (int i = 0; i < _historyLength; i++) {
      _history.add(<String>{});
    }
    // _startShiftTimer(); // Start timer when mcache is active in GossipSub
  }

  /// Starts the periodic timer to shift history windows.
  void start() {
    _shiftTimer?.cancel(); // Cancel existing timer if any
    _shiftTimer = Timer.periodic(_gossipInterval, (_) => shift());
  }

  /// Stops the history window shift timer.
  void stop() {
    _shiftTimer?.cancel();
    _shiftTimer = null;
  }

  /// Generates a unique ID for a message.
  /// Uses (source_peer_id_bytes + sequence_number_bytes) as the message ID.
  // static String getMessageId(pb.Message message) { // Moved to midgen.dart
  //   final fromHex = message.from.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  //   final seqnoHex = message.seqno.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  //   return '$fromHex-$seqnoHex';
  // }

  /// Adds a message to the current history window (window 0) and stores the full message.
  void put(pb.Message message) {
    final messageId = defaultMessageIdFn(message); // Use from midgen.dart
    _history[0].add(messageId);

    // Store the full message for IWANT requests
    if (_messages.containsKey(messageId)) {
      _messages.remove(messageId); // Re-insert to update order for LRU
    }
    _messages[messageId] = message;
    _ensureMessageStoreSize();

    // Also, add a timestamp to the message entry if we were to use MessageCacheWindowEntry
    // For now, _messages map itself handles LRU. TTL needs separate GC for _messages.
  }

  /// Retrieves a message by its ID from the message store.
  pb.Message? getMessage(String messageId) {
    // TODO: Implement TTL check for _messages if not relying solely on LRU for active cleanup.
    return _messages[messageId];
  }
  
  /// Retrieves multiple messages by their IDs from the message store.
  Map<String, pb.Message> getMessages(List<String> messageIds) {
    final Map<String, pb.Message> result = {};
    for (final id in messageIds) {
      final msg = getMessage(id);
      if (msg != null) {
        result[id] = msg;
      }
    }
    return result;
  }


  /// Checks if a message ID has been seen in any of the history windows.
  bool seen(String messageId) {
    for (final window in _history) {
      if (window.contains(messageId)) {
        return true;
      }
    }
    return false;
  }

  /// Gets all message IDs from the current history window (window 0).
  Set<String> getWindow() {
    return Set<String>.from(_history[0]);
  }

  /// Gets message IDs from all history windows.
  List<String> getMessageIds() {
    final List<String> allIds = [];
    for (final window in _history) {
      allIds.addAll(window);
    }
    return allIds;
  }

  /// Shifts the history windows, discarding the oldest and adding a new empty one.
  void shift() {
    if (_history.isNotEmpty) {
      _history.removeLast();
    }
    _history.insert(0, <String>{});
    // print('MCache: Shifted history windows.');

    // GC for _messages (simple TTL based, could be more sophisticated)
    _gcMessages();
  }
  
  void _ensureMessageStoreSize() {
    while (_messages.length > _messageStoreMaxSize) {
      final oldestKey = _messages.keys.first;
      _messages.remove(oldestKey);
    }
  }

  void _gcMessages() {
    // This is a placeholder for a more robust GC for _messages based on _messageStoreTTL.
    // A simple approach: if _messages grows too large, trim.
    // A proper TTL based GC would require storing timestamps with messages in _messages
    // and periodically iterating or checking on access.
    // For now, _ensureMessageStoreSize provides a basic size cap.
    // If _messageStoreTTL is much shorter than history window shifts, many items might expire
    // before being LRU'd by size.
    // A more active GC for _messages might be needed if TTL is critical.
  }

  void dispose() {
    stop(); // Stop the shift timer
    _history.clear();
    _messages.clear();
    print('MessageCache disposed.');
  }
}

import 'dart:convert';
import 'dart:typed_data';
import '../pb/rpc.pb.dart' as pb;

/// A function that computes the ID of a PubSub message, as go-libp2p-pubsub's
/// `MsgIdFunction`.
///
/// Message IDs are binary: they travel as `bytes` in IHAVE, IWANT and
/// IDONTWANT, and nodes of a network must compute the same ID for a message.
/// A Dart ID is a "byte string": each code unit is one byte (0-255), as
/// [messageIdFromBytes] builds. A function that returns other characters gets
/// its ID UTF-8 encoded by [normalizeMessageId].
typedef MessageIdFn = String Function(pb.Message message);

/// The default message ID, as go-libp2p-pubsub's `DefaultMsgIdFn`: the bytes
/// of the message's `from` followed by the bytes of its `seqno`.
String defaultMessageIdFn(pb.Message message) =>
    messageIdFromBytes([...message.from, ...message.seqno]);

/// The message ID whose bytes are [bytes].
String messageIdFromBytes(List<int> bytes) => String.fromCharCodes(bytes);

/// The bytes of the message ID [id], as sent on the wire.
Uint8List messageIdToBytes(String id) => Uint8List.fromList(normalizeMessageId(id).codeUnits);

/// [id] as a byte string: unchanged if each of its code units is a byte,
/// otherwise its UTF-8 encoding.
String normalizeMessageId(String id) {
  for (final unit in id.codeUnits) {
    if (unit > 0xff) return String.fromCharCodes(utf8.encode(id));
  }
  return id;
}

/// [id] in hex, for logs.
String messageIdToHex(String id) =>
    id.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Generates unique sequence numbers for outgoing messages.
///
/// This class helps ensure that messages published by this node have unique
/// and monotonically increasing sequence numbers.
class MessageIdGenerator {
  // The local peer ID is not strictly needed for seqno generation itself,
  // but often the generator is associated with a peer.
  // final PeerId _localPeerId; // Not used in current seqno generation logic

  int _seqnoCounter = 0; // Using int, which can represent Uint64 in Dart if not too large.
                         // For true Uint64 behavior, BigInt might be needed if counter can exceed 2^53.
                         // Or, use DateTime.now().microsecondsSinceEpoch as in PubSub.publish.

  MessageIdGenerator(/*this._localPeerId*/) {
    // Initialize with current time to ensure some level of global uniqueness across restarts,
    // though true monotonicity across restarts requires persistent storage of seqno.
    // For simplicity, we start from a time-based value or 0.
    // Using a time-based initial value makes seqnos larger but less likely to collide
    // if multiple instances run without persistent state.
    _seqnoCounter = DateTime.now().microsecondsSinceEpoch;
  }

  /// Generates the next sequence number as an 8-byte Uint8List (BigEndian).
  Uint8List nextSeqno() {
    _seqnoCounter++;
    final seqnoBytes = Uint8List(8);
    ByteData.view(seqnoBytes.buffer).setUint64(0, _seqnoCounter, Endian.big);
    return seqnoBytes;
  }

  /// Resets the sequence number counter. (Primarily for testing).
  void reset({int initialValue = 0}) {
     _seqnoCounter = initialValue == 0 ? DateTime.now().microsecondsSinceEpoch : initialValue;
  }
}

import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import '../pb/rpc.pb.dart' as pb;

/// A function that computes a unique ID for a PubSub message.
typedef MessageIdFn = String Function(pb.Message message);

/// The default message ID function.
/// It generates an ID by concatenating the hex string representation of
/// the message's `from` field (PeerId bytes) and `seqno` field (sequence number bytes).
String defaultMessageIdFn(pb.Message message) {
  final fromHex = message.from.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final seqnoHex = message.seqno.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$fromHex-$seqnoHex';
}

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

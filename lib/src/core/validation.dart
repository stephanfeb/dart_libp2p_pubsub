import 'message.dart'; // For PubSubMessage
import '../pb/rpc.pb.dart' as pb; // For pb.Message
import 'package:dart_libp2p/core/peer/peer_id.dart'; // For PeerId
// Potentially import 'pubsub.dart' if MessageValidator typedef is needed here,
// or redefine a similar concept.

import 'dart:typed_data'; // For Uint8List

// Default maximum size for a pubsub message, in bytes.
// (1MB as in go-libp2p-pubsub)
const int defaultMaxMessageSize = 1 * 1024 * 1024;

/// Represents the outcome of a message validation step.
enum ValidationResult {
  /// The message is considered valid and should be processed.
  accept,

  /// The message is invalid and should be dropped.
  /// The peer sending this message may be penalized.
  reject,

  /// The message should be ignored (e.g., already seen, not for us).
  /// This typically doesn't penalize the sending peer.
  ignore,
}

// --- Built-in Validators ---
// These will be functions or methods that take a PubSubMessage (or pb.Message)
// and return a ValidationResult.

/// Validates basic message structure and fields.
/// Corresponds to parts of `validateRpcMessage` in Go.
ValidationResult validateMessageStructure(
  PubSubMessage message, {
  int maxMessageSize = defaultMaxMessageSize,
}) {
  final rpcMsg = message.rpcMessage;

  // Check: 'from' field (publisher PeerId raw bytes) must be present.
  // The PubSubMessage.from getter already attempts to parse it.
  // Here, we check the source bytes.
  if (rpcMsg.from.isEmpty) {
    print('Validation: Message rpcMessage.from (source PeerId bytes) is empty.');
    return ValidationResult.reject;
  }

  // Check: 'seqno' field (sequence number raw bytes) must be present.
  if (rpcMsg.seqno.isEmpty) {
    print('Validation: Message rpcMessage.seqno (sequence number bytes) is empty.');
    return ValidationResult.reject;
  }

  // Check: 'topic' field must not be empty.
  if (rpcMsg.topic.isEmpty) {
    print('Validation: Message rpcMessage.topic is empty.');
    return ValidationResult.reject;
  }
  // TODO: Add validation for topic string format if necessary (e.g., valid characters, length).

  // Check: 'data' field payload size.
  if (rpcMsg.data.length > maxMessageSize) {
    print('Validation: Message data size (${rpcMsg.data.length}) exceeds maximum ($maxMessageSize).');
    return ValidationResult.reject;
  }

  // TODO: Consider other structural checks from the proto definition if applicable
  // (e.g., if certain fields are mandatory beyond what .isEmpty checks).

  return ValidationResult.accept;
}

/// Validates message signatures if strict signing is enabled.
/// Corresponds to parts of `validateReceivedMessage` related to signature checks in Go.
ValidationResult validateMessageSignature(PubSubMessage message) {
  // TODO: Implement signature validation if strict signing is required.
  // This involves:
  // 1. Getting the public key from message.from (PeerId).
  // 2. Reconstructing the message data that was signed.
  // 3. Verifying message.signature against the data and public key.
  // This is a complex part and depends on crypto utilities.
  // For now, assuming optional or not strictly enforced at this basic level.
  print('Validation: Signature validation (TODO) for message from ${message.from.toBase58()}');
  return ValidationResult.accept; // Placeholder
}

// --- Other validation aspects from validation_builtin.go to consider ---
// - `validateTopic` (already partially covered by checking topic non-empty)
// - `validateSeqno` (e.g., against a peer's known seqno window)
// - `validateData` (e.g., size limits, content inspection if any)

// The `MessageValidator` typedef in `pubsub.dart` is:
// typedef MessageValidator = bool Function(String topic, dynamic message);
// We might need to adapt this or create a new one that returns ValidationResult
// and takes PubSubMessage.

/// Combines multiple validation steps.
/// This would be used by PubSub core to validate incoming messages.
ValidationResult validateFullMessage(
  PubSubMessage message, {
  int maxMessageSize = defaultMaxMessageSize,
  // BasicSeqnoValidator? seqnoValidator, // Example of how it might be passed
}) {
  var result = validateMessageStructure(message, maxMessageSize: maxMessageSize);
  if (result != ValidationResult.accept) {
    return result;
  }

  result = validateMessageSignature(message);
  if (result != ValidationResult.accept) {
    return result;
  }

  // Add more validation steps here as they are implemented.
  // if (seqnoValidator != null) {
  //   result = seqnoValidator.validate(message);
  //   if (result != ValidationResult.accept) {
  //     return result;
  //   }
  // }

  return ValidationResult.accept;
}

// --- PeerMetadataStore and BasicSeqnoValidator (Ported from validation_builtin.go) ---

/// Interface for storing and retrieving per-peer metadata, primarily for sequence numbers.
abstract class PeerMetadataStore {
  /// Retrieves the metadata (e.g., last seen sequence number as Uint8List) for a peer.
  /// Returns null if no metadata is found.
  Future<Uint8List?> get(PeerId peerId);

  /// Stores metadata for a peer.
  Future<void> put(PeerId peerId, Uint8List metadata);
}

/// A validator that checks message sequence numbers against a persistent store
/// to prevent replays outside the seen cache window.
///
/// This validator requires that messages have sequence numbers.
/// It helps ensure that messages are not replayed, complementing the time-based seen cache.
class BasicSeqnoValidator {
  final PeerMetadataStore _metadataStore;
  // TODO: Consider concurrency control if multiple validations for the same peer
  // can happen concurrently (e.g., using package:synchronized Lock).
  // final Lock _lock = Lock(); // Example from package:synchronized

  BasicSeqnoValidator(this._metadataStore);

  /// Validates the sequence number of the message.
  ///
  /// Returns [ValidationResult.ignore] if the sequence number is not greater
  /// than the last seen sequence number for the peer.
  /// Otherwise, updates the last seen sequence number and returns [ValidationResult.accept].
  Future<ValidationResult> validate(PubSubMessage message) async {
    final peerId = message.from;
    final seqnoBytes = message.rpcMessage.seqno;

    if (seqnoBytes.isEmpty) {
      // This should ideally be caught by validateMessageStructure,
      // but as a safeguard in BasicSeqnoValidator:
      print('BasicSeqnoValidator: Message from $peerId has empty sequence number. Rejecting.');
      return ValidationResult.reject; // Or ignore, depending on strictness for seqno presence
    }

    // Convert seqno bytes to Uint64 (int in Dart for u64)
    // Protobuf bytes are typically BigEndian.
    final seqno = ByteData.view(Uint8List.fromList(seqnoBytes).buffer)
        .getUint64(0, Endian.big);

    // Get current nonce (max seen seqno) for the peer
    // TODO: Add concurrency lock here if needed for the get-put sequence
    // await _lock.synchronized(() async { ... });
    final storedNonceBytes = await _metadataStore.get(peerId);
    int currentNonce = 0;
    if (storedNonceBytes != null && storedNonceBytes.isNotEmpty) {
      if (storedNonceBytes.length == 8) { // Ensure it's a Uint64
        currentNonce = ByteData.view(storedNonceBytes.buffer)
            .getUint64(0, Endian.big);
      } else {
        // Handle malformed nonce bytes - perhaps log and ignore or treat as 0
        print('BasicSeqnoValidator: Malformed nonce bytes for peer $peerId. Length: ${storedNonceBytes.length}');
      }
    }

    if (seqno <= currentNonce) {
      print('BasicSeqnoValidator: Message seqno $seqno from $peerId is not greater than current nonce $currentNonce. Ignoring.');
      return ValidationResult.ignore;
    }

    // If we reach here, seqno > currentNonce.
    // The Go code does a double-check lock here. For simplicity in this initial port,
    // we'll assume that if the first check passes, we proceed to update.
    // A robust implementation might need the double-check or ensure the calling
    // context serializes validation for messages from the same peer.

    // Update the nonce
    final newNonceBytes = Uint8List(8);
    ByteData.view(newNonceBytes.buffer).setUint64(0, seqno, Endian.big);

    try {
      await _metadataStore.put(peerId, newNonceBytes);
    } catch (e) {
      print('BasicSeqnoValidator: Error storing peer nonce for $peerId: $e. Accepting message but nonce not updated.');
      // Still accept the message as it passed the seqno check, but log the store error.
      return ValidationResult.accept;
    }
    
    // print('BasicSeqnoValidator: Message seqno $seqno from $peerId accepted. Nonce updated.');
    return ValidationResult.accept;
    // }); // End of hypothetical lock
  }
}

// Note: The original `NewBasicSeqnoValidator` in Go returns a `ValidatorEx` function.
// Here, we've created a class with a `validate` method.
// Integration into the PubSub validation pipeline will require adapting
// the `PubSub._validators` list and `_validateMessage` method.

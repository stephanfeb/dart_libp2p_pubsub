import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/keys.dart'; // For PrivateKey, PublicKey
// May also need specific crypto algorithm imports if not covered by keys.dart

import '../pb/rpc.pb.dart' as pb; // For pb.Message
import 'message.dart'; // For PubSubMessage, if we operate on it directly

// The message fields that are typically included in the signature.
// This should match how go-libp2p-pubsub constructs the payload for signing.
// Usually: from, data, seqno, topicIDs (or topic in our case).
// The exact byte representation matters.
Uint8List constructMessageSigningPayload(pb.Message message) {
  // Placeholder: This needs to be a canonical serialization of the fields to be signed.
  // Example structure (order and exact fields matter):
  // Bytes from: message.from
  // Bytes data: message.data
  // Bytes seqno: message.seqno
  // Bytes topic: message.topic.codeUnits (UTF-8 of topic string)

  // This is a simplified concatenation. Real implementation needs precise byte construction.
  final List<int> payloadBytes = [];
  payloadBytes.addAll(message.from);
  payloadBytes.addAll(message.data);
  payloadBytes.addAll(message.seqno);
  payloadBytes.addAll(message.topic.codeUnits); // UTF-8 bytes of the topic string

  return Uint8List.fromList(payloadBytes);
}

/// Signs a PubSub RPC Message using the local node's private key.
///
/// This function constructs the signing payload, signs it, and then
/// updates the `signature` (and potentially `key`) field of the message.
///
/// [message] is the protobuf message to be signed. It will be modified in place.
/// [localPrivateKey] is the private key of the local node.
Future<void> signMessage(pb.Message message, PrivateKey localPrivateKey) async {
  // 1. Ensure 'from' field is set to the local peer's ID bytes.
  //    (This should be done by the caller before signing, ensuring message.from
  //     corresponds to localPrivateKey.publicKey.bytes)
  if (message.from.isEmpty) {
    throw ArgumentError('Message "from" field must be set before signing.');
  }

  // 2. Construct the payload to sign.
  //    The signature and key fields should be absent or zeroed when constructing this payload.
  //    Our current constructMessageSigningPayload doesn't explicitly use signature/key.
  final payload = constructMessageSigningPayload(message);

  // 3. Sign the payload.
  final signature = await localPrivateKey.sign(payload);
  message.signature = signature;

  // 4. Optionally, include the public key if the recipient might not have it
  //    or if the signature scheme requires it (e.g., for certain key types).
  //    The pb.Message has a `key` field for this.
  //    message.key = localPrivateKey.publicKey.bytes; // If needed.
  //    For now, we assume the 'from' field (PeerId) is sufficient for the
  //    verifier to obtain the public key.

  print('Message signed. Signature length: ${signature.length}');
}

/// Verifies the signature of a received PubSubMessage.
///
/// [pubsubMessage] is the message wrapper containing the rpc.pb.Message.
///
/// Returns `true` if the signature is valid, `false` otherwise.
/// This function needs access to the public key of the sender.
Future<bool> verifyMessageSignature(PubSubMessage pubsubMessage) async {
  final rpcMessage = pubsubMessage.rpcMessage;

  if (rpcMessage.signature.isEmpty) {
    // STRICT SIGNING: Reject messages without signatures
    print('Verification: Message has no signature. Rejecting (strict mode).');
    return false;
  }

  // 1. Get the sender's public key.
  //    This is typically derived from `rpcMessage.from` (PeerId bytes).
  //    The `pubsubMessage.from` (PeerId object) can be used.
  final senderPeerId = pubsubMessage.from;
  PublicKey? publicKey;
  try {
    // How PeerId.extractPublicKey() or similar works depends on dart_libp2p.
    // It might be: publicKey = senderPeerId.publicKey; (if PeerId embeds it)
    // Or it might need to be fetched from a PeerStore or derived if the PeerId
    // implies the key type (e.g., Ed25519 PeerIds).
    // The `rpcMessage.key` field could also contain the public key.

    // Placeholder: This is a critical step depending on dart_libp2p crypto API.
    // For now, we assume we can get a PublicKey object from senderPeerId.
    // If rpcMessage.key is populated, that should be preferred.
    if (rpcMessage.key.isNotEmpty) {
      // Assuming PublicKey.deserialize or similar exists for unmarshalling.
      // This might also be specific to key types, e.g., Ed25519PublicKey.fromBytes().
      // Assuming a top-level unmarshalPublicKey function from the crypto library.
      publicKey = Ed25519PublicKey.fromRawBytes(Uint8List.fromList(rpcMessage.key));
    } else {
      // This is a simplification. Extracting public key from PeerId bytes
      // without knowing the key type embedded in those bytes is non-trivial.
      // Libp2p PeerIds often embed a multihash of the public key.
      // We'd need a way to get the actual PublicKey object.
      // For Ed25519, PeerId bytes might be directly related to public key bytes
      // after multihash prefix.
      // This is a MAJOR TODO and placeholder.
      print('Verification: TODO - Public key extraction from PeerId ${senderPeerId.toBase58()} or rpcMessage.key is complex.');
      // Attempting a hypothetical extraction for demonstration:
      // publicKey = await someCryptoUtil.publicKeyFromPeerId(senderPeerId);
      // If this fails, verification fails.
      return false; // Cannot verify without a public key.
    }
  } catch (e) {
    print('Verification: Error obtaining public key for ${senderPeerId.toBase58()}: $e');
    return false;
  }

  // 2. Construct the payload that was signed.
  //    This must be identical to how signMessage constructed it.
  final payload = constructMessageSigningPayload(rpcMessage);

  // 3. Verify the signature.
  try {
    final isValid = await publicKey.verify(payload, Uint8List.fromList(rpcMessage.signature));
    if (isValid) {
      print('Verification: Signature VALID for message from ${senderPeerId.toBase58()}');
    } else {
      print('Verification: Signature INVALID for message from ${senderPeerId.toBase58()}');
    }
    return isValid;
  } catch (e) {
    print('Verification: Error during signature verification for ${senderPeerId.toBase58()}: $e');
    return false;
  }
}

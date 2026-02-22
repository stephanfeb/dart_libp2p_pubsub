import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/crypto/pb/crypto.pb.dart' as crypto_pb;

import '../pb/rpc.pb.dart' as pb;
import 'message.dart';

/// The signing prefix used by go-libp2p-pubsub.
const String _signPrefix = 'libp2p-pubsub:';

/// Constructs the signing payload matching go-libp2p-pubsub:
/// "libp2p-pubsub:" + protobuf(message with signature and key cleared).
Uint8List constructMessageSigningPayload(pb.Message message) {
  // Create a copy without signature/key fields by round-tripping through protobuf
  final copy = pb.Message.fromBuffer(message.writeToBuffer());
  copy.clearSignature();
  copy.clearKey();
  final msgBytes = copy.writeToBuffer();
  final prefix = utf8.encode(_signPrefix);
  return Uint8List.fromList([...prefix, ...msgBytes]);
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

  // 4. Include the protobuf-wrapped public key (matches go-libp2p format).
  message.key = localPrivateKey.publicKey.marshal();
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

  // 1. Get the sender's public key from the message's key field,
  //    or extract it from the peer ID (Go omits the key field for Ed25519
  //    inline keys where the key is recoverable from the peer ID).
  final senderPeerId = pubsubMessage.from;
  PublicKey? publicKey;
  if (rpcMessage.key.isNotEmpty) {
    try {
      // Unmarshal protobuf-wrapped public key (matches go-libp2p format)
      final pbKey = crypto_pb.PublicKey.fromBuffer(rpcMessage.key);
      publicKey = publicKeyFromProto(pbKey);
    } catch (e) {
      print('Verification: Error obtaining public key for ${senderPeerId.toBase58()}: $e');
      return false;
    }
  } else {
    // Key not in message — extract from sender's PeerId (Ed25519 inline keys)
    publicKey = await senderPeerId.extractPublicKey();
    if (publicKey == null) {
      print('Verification: Message has no public key and cannot extract from PeerId. Rejecting.');
      return false;
    }
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

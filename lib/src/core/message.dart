import 'dart:typed_data';

import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../pb/rpc.pb.dart' as pb; // For the protobuf Message

/// Represents an internal PubSub message, potentially wrapping the protobuf message
/// and adding extra metadata.
class PubSubMessage {
  /// The underlying protobuf message.
  final pb.Message rpcMessage;

  /// The peer from whom this message was received.
  /// This is null for messages published by the local node.
  final PeerId? receivedFrom;

  // Sequence number, if we decide to use the one from pb.Message.seqno directly
  // or manage it separately. For now, assume it's part of rpcMessage.

  // Validator-specific data that might be attached during validation.
  // dynamic validatorData; // Placeholder if needed

  /// Creates a new [PubSubMessage].
  ///
  /// [rpcMessage] is the protobuf message.
  /// [receivedFrom] is the PeerId of the sender (null if locally originated).
  PubSubMessage({
    required this.rpcMessage,
    this.receivedFrom,
    // this.validatorData,
  });

  /// The topic this message belongs to.
  /// Based on the generated rpc.pb.dart, a message is associated with a single topic string.
  String get topic => rpcMessage.topic;

  /// The actual data payload of the message.
  List<int> get data => rpcMessage.data;

  /// The sequence number of the message.
  List<int> get seqno => rpcMessage.seqno;

  /// The PeerId of the original publisher of the message.
  PeerId get from => PeerId.fromBytes(Uint8List.fromList(rpcMessage.from));

  /// The signature of the message, if present.
  List<int> get signature => rpcMessage.signature;

  /// The key used for the signature, if present.
  List<int> get key => rpcMessage.key;

  @override
  String toString() {
    return 'PubSubMessage{from: ${from.toBase58()}, topic: $topic, seqno: ${seqno.toString()}, receivedFrom: ${receivedFrom?.toBase58() ?? "local"}}';
  }

  // It might be useful to have factory constructors or methods, e.g.:
  // static PubSubMessage fromBytes(List<int> bytes, PeerId receivedFrom) { ... }
  // List<int> toBytes() { ... }
}

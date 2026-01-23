import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/validation.dart';
import 'package:dart_libp2p_pubsub/src/core/message.dart';
import 'package:dart_libp2p_pubsub/src/core/sign.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'dart:typed_data';

// Mock implementation for PeerMetadataStore
class MockPeerMetadataStore implements PeerMetadataStore {
  final Map<String, Uint8List> _store = {};

  @override
  Future<Uint8List?> get(PeerId peerId) async {
    return _store[peerId.toBase58()];
  }

  @override
  Future<void> put(PeerId peerId, Uint8List metadata) async {
    _store[peerId.toBase58()] = metadata;
  }

  void clear() {
    _store.clear();
  }
}

void main() {
  late PeerId localPeerId;

  setUpAll(() async {
    // Generate a single PeerId for all tests to use, to avoid repeated async calls in setUp
    localPeerId = await PeerId.random();
  });
  
  PubSubMessage createTestPubSubMessage({
    PeerId? from,
    String topic = 'test-topic',
    List<int> data = const [1, 2, 3],
    List<int> seqno = const [0,0,0,0,0,0,0,1], // Default to 1 as u64be
  }) {
    final msg = pb.Message();
    msg.from = (from ?? localPeerId).toBytes();
    msg.topic = topic;
    msg.data = Uint8List.fromList(data);
    msg.seqno = Uint8List.fromList(seqno);
    return PubSubMessage(rpcMessage: msg, receivedFrom: from ?? localPeerId);
  }

  group('validateMessageStructure Tests', () {
    test('should accept a valid message', () {
      final message = createTestPubSubMessage();
      expect(validateMessageStructure(message), equals(ValidationResult.accept));
    });

    test('should reject message with empty "from" field', () {
      final pbMsg = pb.Message()
        ..topic = 'test'
        ..data = Uint8List(0)
        ..seqno = Uint8List.fromList([1]);
      // pbMsg.from is not set (empty by default)
      final message = PubSubMessage(rpcMessage: pbMsg, receivedFrom: localPeerId); // receivedFrom is set, but rpcMessage.from is not
      expect(validateMessageStructure(message), equals(ValidationResult.reject));
    });

    test('should reject message with empty "seqno" field', () {
      final pbMsg = pb.Message()
        ..from = localPeerId.toBytes()
        ..topic = 'test'
        ..data = Uint8List(0);
      // pbMsg.seqno is not set
      final message = PubSubMessage(rpcMessage: pbMsg, receivedFrom: localPeerId);
      expect(validateMessageStructure(message), equals(ValidationResult.reject));
    });

    test('should reject message with empty "topic" field', () {
      final message = createTestPubSubMessage(topic: '');
      expect(validateMessageStructure(message), equals(ValidationResult.reject));
    });

    test('should reject message exceeding maxMessageSize', () {
      final oversizedData = Uint8List(defaultMaxMessageSize + 1);
      final message = createTestPubSubMessage(data: oversizedData);
      expect(validateMessageStructure(message), equals(ValidationResult.reject));
    });

    test('should accept message at exactly maxMessageSize', () {
      final data = Uint8List(defaultMaxMessageSize);
      final message = createTestPubSubMessage(data: data);
      expect(validateMessageStructure(message), equals(ValidationResult.accept));
    });
  });

  group('BasicSeqnoValidator Tests', () {
    late BasicSeqnoValidator seqnoValidator;
    late MockPeerMetadataStore mockStore;
    late PeerId peerA;

    setUp(() async {
      mockStore = MockPeerMetadataStore();
      seqnoValidator = BasicSeqnoValidator(mockStore);
      peerA = await PeerId.random(); // Use a different peer for these tests
    });

    Uint8List u64be(int val) {
      final bytes = Uint8List(8);
      ByteData.view(bytes.buffer).setUint64(0, val, Endian.big);
      return bytes;
    }

    test('should accept message with higher sequence number', () async {
      final message = createTestPubSubMessage(from: peerA, seqno: u64be(1));
      expect(await seqnoValidator.validate(message), equals(ValidationResult.accept));
      final stored = await mockStore.get(peerA);
      expect(stored, equals(u64be(1)));
    });

    test('should ignore message with same sequence number', () async {
      await mockStore.put(peerA, u64be(1)); // Pre-store seqno 1
      final message = createTestPubSubMessage(from: peerA, seqno: u64be(1));
      expect(await seqnoValidator.validate(message), equals(ValidationResult.ignore));
    });

    test('should ignore message with lower sequence number', () async {
      await mockStore.put(peerA, u64be(5)); // Pre-store seqno 5
      final message = createTestPubSubMessage(from: peerA, seqno: u64be(4));
      expect(await seqnoValidator.validate(message), equals(ValidationResult.ignore));
    });

    test('should accept message if no prior sequence number stored', () async {
      final message = createTestPubSubMessage(from: peerA, seqno: u64be(100));
      expect(await seqnoValidator.validate(message), equals(ValidationResult.accept));
      expect(await mockStore.get(peerA), equals(u64be(100)));
    });
    
    test('should reject message with empty sequence number', () async {
      final message = createTestPubSubMessage(from: peerA, seqno: []);
      expect(await seqnoValidator.validate(message), equals(ValidationResult.reject));
    });

    test('should handle malformed stored nonce (e.g. treat as 0 and accept higher)', () async {
      await mockStore.put(peerA, Uint8List.fromList([1,2,3])); // Malformed (not 8 bytes)
      final message = createTestPubSubMessage(from: peerA, seqno: u64be(1));
      expect(await seqnoValidator.validate(message), equals(ValidationResult.accept));
      expect(await mockStore.get(peerA), equals(u64be(1)));
    });
  });
  
  group('validateMessageSignature Tests', () {
    late KeyPair keyPair;
    late PeerId signedPeerId;

    setUp(() async {
      keyPair = await crypto_ed25519.generateEd25519KeyPair();
      signedPeerId = await PeerId.fromPublicKey(keyPair.publicKey);
    });

    Future<PubSubMessage> createSignedMessage({
      required KeyPair signerKeyPair,
      required PeerId from,
      String topic = 'test-topic',
      List<int> data = const [1, 2, 3],
      bool includeSignature = true,
      bool includeKey = true,
      Uint8List? overrideKey,
    }) async {
      final msg = pb.Message();
      msg.from = from.toBytes();
      msg.topic = topic;
      msg.data = Uint8List.fromList(data);
      msg.seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1]);

      if (includeKey) {
        msg.key = overrideKey ?? signerKeyPair.publicKey.raw;
      }

      if (includeSignature) {
        await signMessage(msg, signerKeyPair.privateKey);
      }

      return PubSubMessage(rpcMessage: msg, receivedFrom: from);
    }

    test('should accept message with valid signature and matching key-PeerId', () async {
      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
      );
      expect(await validateMessageSignature(message), equals(ValidationResult.accept));
    });

    test('should reject message without signature (strict policy)', () async {
      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
        includeSignature: false,
      );
      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });

    test('should reject message without public key', () async {
      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
        includeKey: false,
      );
      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });

    test('should reject message with key-PeerId mismatch', () async {
      // Create a different keypair whose key doesn't match signedPeerId
      final otherKeyPair = await crypto_ed25519.generateEd25519KeyPair();

      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
        overrideKey: otherKeyPair.publicKey.raw,
      );
      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });

    test('should reject message with tampered data', () async {
      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
      );

      // Tamper with data after signing
      message.rpcMessage.data = Uint8List.fromList([9, 9, 9]);

      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });

    test('should reject message with invalid signature bytes', () async {
      final message = await createSignedMessage(
        signerKeyPair: keyPair,
        from: signedPeerId,
      );

      // Corrupt the signature
      message.rpcMessage.signature = Uint8List.fromList(List.filled(64, 0));

      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });

    test('should reject message with malformed public key', () async {
      final msg = pb.Message()
        ..from = signedPeerId.toBytes()
        ..topic = 'test'
        ..data = Uint8List.fromList([1, 2, 3])
        ..seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1])
        ..key = Uint8List.fromList([1, 2, 3]) // Malformed key (wrong length)
        ..signature = Uint8List.fromList(List.filled(64, 0));

      final message = PubSubMessage(rpcMessage: msg, receivedFrom: signedPeerId);
      expect(await validateMessageSignature(message), equals(ValidationResult.reject));
    });
  });

  group('validateFullMessage Tests', () {
    late KeyPair keyPair;
    late PeerId signedPeerId;

    setUp(() async {
      keyPair = await crypto_ed25519.generateEd25519KeyPair();
      signedPeerId = await PeerId.fromPublicKey(keyPair.publicKey);
    });

    test('should accept valid signed message', () async {
      final msg = pb.Message()
        ..from = signedPeerId.toBytes()
        ..topic = 'test-topic'
        ..data = Uint8List.fromList([1, 2, 3])
        ..seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1])
        ..key = keyPair.publicKey.raw;

      await signMessage(msg, keyPair.privateKey);

      final message = PubSubMessage(rpcMessage: msg, receivedFrom: signedPeerId);
      expect(await validateFullMessage(message), equals(ValidationResult.accept));
    });

    test('should reject message failing structural validation', () async {
      final msg = pb.Message()
        ..from = signedPeerId.toBytes()
        ..topic = '' // Empty topic - should fail structural validation
        ..data = Uint8List.fromList([1, 2, 3])
        ..seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1])
        ..key = keyPair.publicKey.raw;

      await signMessage(msg, keyPair.privateKey);

      final message = PubSubMessage(rpcMessage: msg, receivedFrom: signedPeerId);
      expect(await validateFullMessage(message), equals(ValidationResult.reject));
    });

    test('should reject message failing signature validation', () async {
      final msg = pb.Message()
        ..from = signedPeerId.toBytes()
        ..topic = 'test-topic'
        ..data = Uint8List.fromList([1, 2, 3])
        ..seqno = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 1]);
      // No signature or key - should fail signature validation

      final message = PubSubMessage(rpcMessage: msg, receivedFrom: signedPeerId);
      expect(await validateFullMessage(message), equals(ValidationResult.reject));
    });
  });
}

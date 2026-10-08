import 'dart:async';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p_pubsub/src/core/sign.dart';
import 'package:dart_libp2p_pubsub/src/core/topic.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:dart_libp2p_pubsub/src/util/midgen.dart';
import 'package:test/test.dart';

import 'message_propagation_test.dart'
    show MockHost, MockNetwork, TestNetworkManager;

/// One in-memory PubSub node.
class _Node {
  final MockHost host;
  final PubSub pubsub;
  final GossipSubRouter router;
  final KeyPair keyPair;
  final List<PubSubMessage> received = [];

  _Node(this.host, this.pubsub, this.router, this.keyPair);

  PeerId get id => host.id;
}

Future<_Node> _createNode(
  TestNetworkManager manager, {
  int validateThrottle = defaultValidateThrottle,
  GossipSubParams? params,
  MessageSignaturePolicy signaturePolicy = MessageSignaturePolicy.strictSign,
  bool noAuthor = false,
  MessageIdFn messageIdFn = defaultMessageIdFn,
}) async {
  final keyPair = await generateEd25519KeyPair();
  final peerId = PeerId.fromPublicKey(keyPair.publicKey);
  final host = MockHost(peerId, keyPair.privateKey);
  (host.network as MockNetwork).manager = manager;
  manager.registerNetwork(peerId, host.network as MockNetwork);

  final router = GossipSubRouter(
      params: params, scoreParams: _scoreParams, scoreThresholds: _thresholds);
  final pubsub = PubSub(host, router,
      privateKey: keyPair.privateKey,
      validateThrottle: validateThrottle,
      signaturePolicy: signaturePolicy,
      noAuthor: noAuthor,
      messageIdFn: messageIdFn);
  await pubsub.start();
  await router.start();
  return _Node(host, pubsub, router, keyPair);
}

/// Scores invalid messages on the test topic: -1 per invalid message
/// squared, as the old default.
final _scoreParams = PeerScoreParams(topics: {
  'validation-topic': TopicScoreParams(
    topicWeight: 1,
    invalidMessageDeliveriesWeight: -1,
    invalidMessageDeliveriesDecay: scoreParameterDecay(const Duration(hours: 1)),
  ),
});

const _thresholds = PeerScoreThresholds(
    gossipThreshold: -10, publishThreshold: -50, graylistThreshold: -80);

/// The invalid message deliveries of [peer] counted by [node].
double _invalid(_Node node, PeerId peer) =>
    node.router.score!.snapshot(peer)?.topics['validation-topic']?.invalidMessageDeliveries ?? 0;

int _seq = 0;

/// Builds a message on [topic] authored and signed by [author].
Future<pb.Message> _signedMessage(
    _Node author, String topic, List<int> data) async {
  final seqno = Uint8List(8);
  ByteData.view(seqno.buffer).setUint64(0, ++_seq);
  final msg = pb.Message()
    ..from = author.id.toBytes()
    ..data = data
    ..seqno = seqno
    ..topic = topic;
  await signMessage(msg, author.keyPair.privateKey);
  return msg;
}

/// Delivers [msg] to [receiver] as if [sender] had sent it, and returns the
/// IDs that the receiver accepted. PubSub delivers accepted messages to its
/// subscribers in the same way.
Future<Set<String>> _receive(
    _Node receiver, _Node sender, pb.Message msg) async {
  // The sender speaks pubsub, as if it had opened a stream.
  await receiver.router.addPeer(sender.id, '/meshsub/1.1.0');
  final accepted =
      await receiver.router.handleRpc(sender.id, pb.RPC()..publish.add(msg));
  if (accepted.contains(receiver.pubsub.messageIdFn(msg))) {
    receiver.pubsub.deliverReceivedMessage(
        PubSubMessage(rpcMessage: msg, receivedFrom: sender.id));
  }
  return accepted;
}

void main() {
  const topic = 'validation-topic';
  late TestNetworkManager manager;
  final List<_Node> nodes = [];

  setUp(() {
    manager = TestNetworkManager();
    nodes.clear();
  });

  tearDown(() async {
    for (final n in nodes) {
      await n.pubsub.stop();
    }
  });

  Future<_Node> node(
      {int validateThrottle = defaultValidateThrottle,
      GossipSubParams? params,
      MessageSignaturePolicy signaturePolicy = MessageSignaturePolicy.strictSign,
      bool noAuthor = false,
      MessageIdFn messageIdFn = defaultMessageIdFn}) async {
    final n = await _createNode(manager,
        validateThrottle: validateThrottle,
        params: params,
        signaturePolicy: signaturePolicy,
        noAuthor: noAuthor,
        messageIdFn: messageIdFn);
    nodes.add(n);
    return n;
  }

  group('Validation in a 3-node chain A - B - C', () {
    late _Node a, b, c;

    setUp(() async {
      // A sends no IHAVE gossip (DLazy 0) and does not flood publish, so C
      // can get A's message only through B.
      a = await node(params: GossipSubParams(DLazy: 0, floodPublish: false));
      b = await node();
      c = await node();

      for (final n in [b, c]) {
        n.pubsub
            .subscribe(topic)
            .stream
            .listen((m) => n.received.add(m as PubSubMessage));
      }
      for (final n in [a, b, c]) {
        await n.router.join(Topic(topic));
      }
      // Let the SUBSCRIBE announcements settle, then set the chain mesh.
      await Future.delayed(const Duration(milliseconds: 200));
      a.router.mesh[topic] = {b.id};
      b.router.mesh[topic] = {a.id, c.id};
      c.router.mesh[topic] = {b.id};
    });

    Future<void> publishFromA(String text) async {
      await a.pubsub.publish(topic, Uint8List.fromList(text.codeUnits));
      await Future.delayed(const Duration(milliseconds: 300));
    }

    test('accept: B delivers to its app and forwards to C', () async {
      b.pubsub.registerTopicValidator(
          topic, (from, msg) => ValidationResult.accept);
      await publishFromA('hello');

      expect(b.received, hasLength(1));
      expect(c.received, hasLength(1));
      expect(c.received.single.receivedFrom, b.id);
      expect(
          _invalid(b, a.id),
          0);
    });

    test(
        'reject: C never sees the message, B app does not get it, A is penalised',
        () async {
      PeerId? seenFrom;
      b.pubsub.registerTopicValidator(topic, (from, msg) {
        seenFrom = from;
        return ValidationResult.reject;
      });
      await publishFromA('bad');

      expect(seenFrom, a.id);
      expect(b.received, isEmpty);
      expect(c.received, isEmpty);
      expect(_invalid(b, a.id), 1);
      // Weight -1 * 1^2, topic weight 1.
      expect(b.router.score!.score(a.id), closeTo(-1.0, 1e-9));
    });

    test('ignore: C never sees the message and A is not penalised', () async {
      b.pubsub.registerTopicValidator(
          topic, (from, msg) => ValidationResult.ignore);
      await publishFromA('not for me');

      expect(b.received, isEmpty);
      expect(c.received, isEmpty);
      expect(
          _invalid(b, a.id),
          0);
      expect(b.router.score!.score(a.id), 0.0);
    });

    test('async validator: B waits for the result before it forwards',
        () async {
      b.pubsub.registerTopicValidator(topic, (from, msg) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return String.fromCharCodes(msg.data) == 'good'
            ? ValidationResult.accept
            : ValidationResult.reject;
      });
      await publishFromA('good');
      await publishFromA('evil');

      expect(b.received.map((m) => String.fromCharCodes(m.data)), ['good']);
      expect(c.received.map((m) => String.fromCharCodes(m.data)), ['good']);
      expect(
          _invalid(b, a.id),
          1);
    });

    test(
        'legacy registerMessageValidator: false rejects and penalises, true accepts',
        () async {
      final seenTopics = <String>[];
      b.pubsub.registerMessageValidator((t, message) {
        seenTopics.add(t);
        expect(message, isA<PubSubMessage>());
        return String.fromCharCodes((message as PubSubMessage).data) != 'spam';
      });
      await publishFromA('spam');
      await publishFromA('ham');

      expect(seenTopics, [topic, topic]);
      expect(b.received.map((m) => String.fromCharCodes(m.data)), ['ham']);
      expect(c.received.map((m) => String.fromCharCodes(m.data)), ['ham']);
      expect(
          _invalid(b, a.id),
          1);
    });

    test('a local validator also checks messages that the node publishes',
        () async {
      a.pubsub.registerTopicValidator(topic, (from, msg) {
        expect(from, a.id);
        return ValidationResult.reject;
      });
      await publishFromA('blocked at the source');

      expect(b.received, isEmpty);
      expect(c.received, isEmpty);
    });
  });

  group('Validation pipeline', () {
    late _Node sender, other, receiver;

    setUp(() async {
      sender = await node();
      other = await node();
    });

    test('duplicates are dropped before validation and are not validated again',
        () async {
      receiver = await node();
      receiver.pubsub
          .subscribe(topic)
          .stream
          .listen((m) => receiver.received.add(m as PubSubMessage));
      var calls = 0;
      receiver.pubsub.registerTopicValidator(topic, (from, msg) {
        calls++;
        return ValidationResult.accept;
      });
      final msg = await _signedMessage(sender, topic, [1]);

      expect(await _receive(receiver, sender, msg), hasLength(1));
      expect(await _receive(receiver, other, msg), isEmpty);
      expect(await _receive(receiver, sender, msg), isEmpty);
      expect(calls, 1);
      expect(receiver.received, hasLength(1));
    });

    test(
        'a rejected message is marked seen: its duplicates are not validated, and their senders are penalised',
        () async {
      receiver = await node();
      var calls = 0;
      receiver.pubsub.registerTopicValidator(topic, (from, msg) {
        calls++;
        return ValidationResult.reject;
      });
      final msg = await _signedMessage(sender, topic, [2]);

      expect(await _receive(receiver, sender, msg), isEmpty);
      expect(await _receive(receiver, other, msg), isEmpty);
      expect(calls, 1);
      expect(
          _invalid(receiver, sender.id),
          1);
      expect(
          _invalid(receiver, other.id),
          1);
    });

    test('copies of one message in flight at the same time are validated once',
        () async {
      receiver = await node();
      var calls = 0;
      final gate = Completer<void>();
      receiver.pubsub.registerTopicValidator(topic, (from, msg) async {
        calls++;
        await gate.future;
        return ValidationResult.accept;
      });
      final msg = await _signedMessage(sender, topic, [3]);

      final first = _receive(receiver, sender, msg);
      final second = _receive(receiver, other, msg);
      gate.complete();
      expect(await first, hasLength(1));
      expect(await second, isEmpty);
      expect(calls, 1);
    });

    test(
        'a validator that does not complete in time gives ignore, without a penalty',
        () async {
      receiver = await node();
      receiver.pubsub
          .subscribe(topic)
          .stream
          .listen((m) => receiver.received.add(m as PubSubMessage));
      final never = Completer<ValidationResult>();
      receiver.pubsub.registerTopicValidator(topic, (from, msg) => never.future,
          timeout: const Duration(milliseconds: 100));
      final msg = await _signedMessage(sender, topic, [4]);

      final sw = Stopwatch()..start();
      expect(await _receive(receiver, sender, msg), isEmpty);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(receiver.received, isEmpty);
      expect(
          _invalid(receiver, sender.id),
          0);
    });

    test('the PubSub validatorTimeout is the default for topic validators',
        () async {
      final keyPair = await generateEd25519KeyPair();
      final host =
          MockHost(PeerId.fromPublicKey(keyPair.publicKey), keyPair.privateKey);
      final ps = PubSub(host, GossipSubRouter(),
          privateKey: keyPair.privateKey,
          validatorTimeout: const Duration(milliseconds: 50));
      ps.registerTopicValidator(
          topic, (from, msg) => Completer<ValidationResult>().future);
      final msg = await _signedMessage(sender, topic, [5]);

      final result = await ps.validateMessage(
          PubSubMessage(rpcMessage: msg, receivedFrom: sender.id));
      expect(result, ValidationResult.ignore);
      await ps.stop();
    });

    test('a validator that throws gives ignore', () async {
      receiver = await node();
      receiver.pubsub.registerTopicValidator(
          topic, (from, msg) => throw StateError('bug'));
      final msg = await _signedMessage(sender, topic, [6]);

      expect(await _receive(receiver, sender, msg), isEmpty);
      expect(
          _invalid(receiver, sender.id),
          0);
    });

    test(
        'global throttle: messages over the limit are ignored without a penalty',
        () async {
      receiver = await node(validateThrottle: 2);
      var calls = 0;
      final gate = Completer<void>();
      receiver.pubsub.registerTopicValidator(topic, (from, msg) async {
        calls++;
        await gate.future;
        return ValidationResult.accept;
      });
      final msgs = [
        for (var i = 0; i < 3; i++)
          await _signedMessage(sender, topic, [10 + i])
      ];

      final results = [for (final m in msgs) _receive(receiver, sender, m)];
      // The third message finds the throttle full and is dropped at once.
      expect(await results[2], isEmpty);
      gate.complete();
      expect(await results[0], hasLength(1));
      expect(await results[1], hasLength(1));
      expect(calls, 2);
      expect(
          _invalid(receiver, sender.id),
          0);
    });

    test('per-topic concurrency: runs over the limit are ignored', () async {
      receiver = await node();
      var calls = 0;
      final gate = Completer<void>();
      receiver.pubsub.registerTopicValidator(topic, (from, msg) async {
        calls++;
        await gate.future;
        return ValidationResult.accept;
      }, concurrency: 1);
      final m1 = await _signedMessage(sender, topic, [20]);
      final m2 = await _signedMessage(sender, topic, [21]);

      final r1 = _receive(receiver, sender, m1);
      final r2 = _receive(receiver, sender, m2);
      expect(await r2, isEmpty);
      gate.complete();
      expect(await r1, hasLength(1));
      expect(calls, 1);
    });

    test('a bad signature is rejected before the topic validator runs',
        () async {
      receiver = await node();
      var calls = 0;
      receiver.pubsub.registerTopicValidator(topic, (from, msg) {
        calls++;
        return ValidationResult.accept;
      });
      final msg = await _signedMessage(sender, topic, [7]);
      msg.data = [8]; // Signature no longer matches.

      expect(await _receive(receiver, sender, msg), isEmpty);
      expect(calls, 0);
      expect(
          _invalid(receiver, sender.id),
          1);
    });

    test('register and unregister topic validators', () async {
      receiver = await node();
      receiver.pubsub.registerTopicValidator(
          topic, (from, msg) => ValidationResult.reject);
      expect(
          () => receiver.pubsub.registerTopicValidator(
              topic, (from, msg) => ValidationResult.accept),
          throwsStateError);
      expect(receiver.pubsub.unregisterTopicValidator(topic), isTrue);
      expect(receiver.pubsub.unregisterTopicValidator(topic), isFalse);

      final msg = await _signedMessage(sender, topic, [9]);
      expect(await _receive(receiver, sender, msg), hasLength(1));
    });
  });

  group('Seen cache and signatures', () {
    late _Node receiver, sender, attacker;

    setUp(() async {
      receiver = await node();
      sender = await node();
      attacker = await node();
    });

    test('a forged copy with a bad signature does not block the genuine message', () async {
      final genuine = await _signedMessage(sender, topic, [1, 2, 3]);
      // Same from and seqno, so the same ID, but a different payload.
      final forged = pb.Message()
        ..mergeFromMessage(genuine)
        ..data = [6, 6, 6];

      expect(await _receive(receiver, attacker, forged), isEmpty);
      expect(await _receive(receiver, sender, genuine), equals({defaultMessageIdFn(genuine)}));
    });

    test('forwarding the genuine message after a forged one is not penalised', () async {
      final genuine = await _signedMessage(sender, topic, [1, 2, 3]);
      final forged = pb.Message()
        ..mergeFromMessage(genuine)
        ..data = [6, 6, 6];
      await _receive(receiver, attacker, forged);
      await _receive(receiver, sender, genuine);
      // A third peer forwards the genuine message: a duplicate, no penalty.
      final forwarder = await node();
      expect(await _receive(receiver, forwarder, genuine), isEmpty);
      expect(_invalid(receiver, forwarder.id), 0);
    });
  });

  group('Signature policies, as go-libp2p-pubsub', () {
    /// A content-based ID, as networks without authors use.
    String contentId(pb.Message m) => String.fromCharCodes(m.data);

    pb.Message unsigned(List<int> data, {List<int>? from}) {
      final m = pb.Message()
        ..topic = topic
        ..data = data;
      if (from != null) {
        m
          ..from = from
          ..seqno = [1, 2, 3, 4, 5, 6, 7, 8];
      }
      return m;
    }

    test('strictNoSign + noAuthor: messages have no author or signature, and are accepted', () async {
      final a = await node(signaturePolicy: MessageSignaturePolicy.strictNoSign, noAuthor: true, messageIdFn: contentId);
      final b = await node(signaturePolicy: MessageSignaturePolicy.strictNoSign, noAuthor: true, messageIdFn: contentId);
      final received = <PubSubMessage>[];
      b.pubsub.subscribe(topic).stream.listen((m) => received.add(m as PubSubMessage));

      final msg = unsigned([1, 2, 3]);
      expect(await _receive(b, a, msg), {contentId(msg)});
      await Future.delayed(const Duration(milliseconds: 20));
      expect(received.single.data, [1, 2, 3]);
    });

    test('strictNoSign rejects a signed message and one with author data', () async {
      final b = await node(signaturePolicy: MessageSignaturePolicy.strictNoSign, noAuthor: true, messageIdFn: contentId);
      final a = await node();
      expect(await _receive(b, a, await _signedMessage(a, topic, [1])), isEmpty);
      expect(await _receive(b, a, unsigned([2], from: a.id.toBytes())), isEmpty);
    });

    test('strictSign rejects an unsigned message', () async {
      final b = await node();
      final a = await node();
      expect(await _receive(b, a, unsigned([1], from: a.id.toBytes())), isEmpty);
      expect(_invalid(b, a.id), 1);
    });

    test('laxSign accepts an unsigned message but checks a signature that is present', () async {
      final b = await node(signaturePolicy: MessageSignaturePolicy.laxSign);
      final a = await node();
      expect(await _receive(b, a, unsigned([1], from: a.id.toBytes())), hasLength(1));
      final forged = await _signedMessage(a, topic, [2]);
      forged.data = [3];
      expect(await _receive(b, a, forged), isEmpty);
    });

    test('a message that claims to be ours but comes from a peer is rejected', () async {
      final b = await node();
      final a = await node();
      final fake = await _signedMessage(b, topic, [1]); // Authored by b itself.
      expect(await _receive(b, a, fake), isEmpty);
      expect(_invalid(b, a.id), 1);
    });

    test('noAuthor publish omits from and seqno and does not sign', () async {
      final a = await node(signaturePolicy: MessageSignaturePolicy.strictNoSign, noAuthor: true, messageIdFn: contentId);
      final published = <PubSubMessage>[];
      a.pubsub.subscribe(topic).stream.listen((m) => published.add(m as PubSubMessage));
      await a.pubsub.publish(topic, Uint8List.fromList([9]));
      await Future.delayed(const Duration(milliseconds: 20));
      final m = published.single.rpcMessage;
      expect(m.from, isEmpty);
      expect(m.seqno, isEmpty);
      expect(m.signature, isEmpty);
    });
  });

  group('Blacklist, as go-libp2p-pubsub', () {
    test('a message from a blacklisted peer is dropped without being marked seen', () async {
      final receiver = await node();
      final bad = await node();
      final good = await node();
      receiver.pubsub.blacklistPeer(bad.id);
      final msg = await _signedMessage(good, topic, [1]);
      expect(await _receive(receiver, bad, msg), isEmpty);
      // The copy from a good peer is still accepted.
      expect(await _receive(receiver, good, msg), hasLength(1));
      expect(_invalid(receiver, bad.id), 0, reason: 'dropped, not penalised as invalid');
    });

    test('a message written by a blacklisted peer is dropped even when a good peer forwards it', () async {
      final receiver = await node();
      final author = await node();
      final forwarder = await node();
      receiver.pubsub.blacklistPeer(author.id);
      expect(await _receive(receiver, forwarder, await _signedMessage(author, topic, [1])), isEmpty);
      expect(await _receive(receiver, forwarder, await _signedMessage(forwarder, topic, [2])), hasLength(1));
    });
  });

  test('messages for topics we do not subscribe to are ignored before validation, as go-libp2p-pubsub', () async {
    final receiver = await node();
    final sender = await node();
    final validated = <String>[];
    for (final t in [topic, 'not-subscribed']) {
      receiver.pubsub.registerTopicValidator(t, (from, m) {
        validated.add(m.topic);
        return ValidationResult.accept;
      });
    }
    receiver.pubsub.subscribe(topic).stream.listen((m) => receiver.received.add(m as PubSubMessage));
    await Future.delayed(const Duration(milliseconds: 100));

    final rpc = pb.RPC()
      ..publish.add(await _signedMessage(sender, 'not-subscribed', [1]))
      ..publish.add(await _signedMessage(sender, topic, [2]));
    await sender.pubsub.comms.sendRpc(receiver.id, rpc, sender.router.protocols.first);
    await Future.delayed(const Duration(milliseconds: 300));

    expect(validated, [topic]);
    expect(receiver.received.map((m) => m.topic), [topic]);
  });
}

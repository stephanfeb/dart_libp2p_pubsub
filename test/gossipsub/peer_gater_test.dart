import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:test/test.dart';

import '../integration/message_propagation_test.dart' show MockHost;

void main() {
  test('PeerGater, as go-libp2p-pubsub TestPeerGater', () async {
    final keyPair = await generateEd25519KeyPair();
    final host = MockHost(PeerId.fromPublicKey(keyPair.publicKey), keyPair.privateKey);
    final peerA = PeerId.fromPublicKey((await generateEd25519KeyPair()).publicKey);
    const peerAip = '1.2.3.4';
    var now = Duration.zero;

    final params = PeerGaterParams(threshold: .1, globalDecay: .9, sourceDecay: .999);
    params.validate();
    final pg = PeerGater(params, host, clock: () => now, getIP: (p) => p == peerA ? peerAip : '<wtf>');

    pg.addPeer(peerA);
    expect(pg.acceptFrom(peerA), AcceptStatus.all);

    pg.validateMessage();
    expect(pg.acceptFrom(peerA), AcceptStatus.all);

    pg.rejectMessage(peerA, 'validation queue full');
    expect(pg.acceptFrom(peerA), AcceptStatus.all);

    pg.rejectMessage(peerA, 'validation throttled');
    expect(pg.acceptFrom(peerA), AcceptStatus.all);

    for (var i = 0; i < 100; i++) {
      pg.rejectMessage(peerA, 'validation ignored');
      pg.rejectMessage(peerA, 'validation failed');
    }
    expect(Iterable.generate(1000, (_) => pg.acceptFrom(peerA)), contains(AcceptStatus.control));

    for (var i = 0; i < 100; i++) {
      pg.deliverMessage(peerA, 'topic');
    }
    expect(Iterable.generate(1000, (_) => pg.acceptFrom(peerA)), contains(AcceptStatus.all));

    for (var i = 0; i < 100; i++) {
      pg.decay();
    }
    expect(pg.acceptFrom(peerA), AcceptStatus.all);

    pg.removePeer(peerA);
    expect(pg.tracksPeer(peerA), isFalse);
    expect(pg.tracksIp(peerAip), isTrue, reason: 'kept for retainStats');

    now += params.retainStats + const Duration(seconds: 1);
    pg.decay();
    expect(pg.tracksIp(peerAip), isFalse);
  });

  test('PeerGater accepts all once throttling has been quiet for the quiet period', () async {
    final keyPair = await generateEd25519KeyPair();
    final host = MockHost(PeerId.fromPublicKey(keyPair.publicKey), keyPair.privateKey);
    final peer = PeerId.fromPublicKey((await generateEd25519KeyPair()).publicKey);
    var now = Duration.zero;
    final pg = PeerGater(PeerGaterParams(), host, clock: () => now, getIP: (_) => '1.1.1.1');
    pg.addPeer(peer);
    pg.validateMessage();
    pg.rejectMessage(peer, 'validation throttled');
    for (var i = 0; i < 100; i++) {
      pg.rejectMessage(peer, 'validation failed');
    }
    expect(Iterable.generate(1000, (_) => pg.acceptFrom(peer)), contains(AcceptStatus.control));
    now += const Duration(minutes: 1, seconds: 1);
    expect(Iterable.generate(1000, (_) => pg.acceptFrom(peer)), everyElement(AcceptStatus.all));
  });

  test('PeerGaterParams validates as go-libp2p-pubsub', () {
    PeerGaterParams().validate();
    expect(() => PeerGaterParams(threshold: 0).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(globalDecay: 1).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(sourceDecay: 0).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(decayInterval: const Duration(milliseconds: 500)).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(quiet: Duration.zero).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(ignoreWeight: 0.5).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(rejectWeight: 0.5).validate(), throwsArgumentError);
    expect(() => PeerGaterParams(duplicateWeight: 0).validate(), throwsArgumentError);
  });
}

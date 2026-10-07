import 'dart:typed_data';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/network/network.dart';
import 'package:dart_libp2p/core/network/notifiee.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/src/core/notify.dart';
import 'package:test/test.dart';

/// A network that records its notifiees and the connections to each peer.
class _FakeNetwork implements Network {
  final List<Notifiee> notifiees = [];
  final Map<PeerId, List<Conn>> connections = {};

  @override
  void notify(Notifiee notifiee) => notifiees.add(notifiee);

  @override
  void stopNotify(Notifiee notifiee) => notifiees.remove(notifiee);

  @override
  List<Conn> connsToPeer(PeerId peerId) => connections[peerId] ?? [];

  /// Opens a connection to [peer] and notifies, as the swarm does.
  Future<Conn> openConn(PeerId peer) async {
    final conn = _FakeConn(peer);
    connections.putIfAbsent(peer, () => []).add(conn);
    for (final n in List.of(notifiees)) {
      await n.connected(this, conn);
    }
    return conn;
  }

  /// Closes [conn] and notifies, as the swarm does.
  Future<void> closeConn(Conn conn) async {
    connections[conn.remotePeer]?.remove(conn);
    for (final n in List.of(notifiees)) {
      await n.disconnected(this, conn);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConn implements Conn {
  @override
  final PeerId remotePeer;

  _FakeConn(this.remotePeer);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHost implements Host {
  @override
  final _FakeNetwork network = _FakeNetwork();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PeerNotifier', () {
    late _FakeHost host;
    late PeerNotifier notifier;
    late PeerId peer;
    late List<PeerId> connected;
    late List<PeerId> disconnected;

    setUp(() async {
      host = _FakeHost();
      notifier = PeerNotifier(host);
      // A minimal identity multihash.
      peer = PeerId.fromBytes(Uint8List.fromList([0x00, 0x01, 0x01]));
      connected = [];
      disconnected = [];
      notifier.onPeerConnected(connected.add);
      notifier.onPeerDisconnected(disconnected.add);
    });

    test('registers with the network of the host', () {
      expect(host.network.notifiees, hasLength(1));
    });

    test('calls the connected callbacks for each new connection', () async {
      await host.network.openConn(peer);
      expect(connected, equals([peer]));
      await host.network.openConn(peer);
      expect(connected, equals([peer, peer]));
      expect(disconnected, isEmpty);
    });

    test('calls the disconnected callbacks when the last connection closes', () async {
      final conn1 = await host.network.openConn(peer);
      final conn2 = await host.network.openConn(peer);

      await host.network.closeConn(conn1);
      expect(disconnected, isEmpty);

      await host.network.closeConn(conn2);
      expect(disconnected, equals([peer]));
    });

    test('a callback that throws does not stop the others', () async {
      final calls = <PeerId>[];
      final n = PeerNotifier(host)
        ..onPeerConnected((_) => throw StateError('boom'))
        ..onPeerConnected(calls.add);
      await host.network.openConn(peer);
      expect(calls, equals([peer]));
      n.dispose();
    });

    test('dispose stops the notifications', () async {
      notifier.dispose();
      expect(host.network.notifiees, isEmpty);

      final conn = await host.network.openConn(peer);
      await host.network.closeConn(conn);
      expect(connected, isEmpty);
      expect(disconnected, isEmpty);
    });
  });
}

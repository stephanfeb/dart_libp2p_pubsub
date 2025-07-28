import 'dart:async';

import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/peer_gater.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart';
// event_bus and interfaces might not be directly needed for SimplePeerGater tests unless it uses them.
// import 'package:dart_libp2p/core/event/bus.dart' as event_bus;
// import 'package:dart_libp2p/core/interfaces.dart'; // For Connectedness, EvtPeerConnectednessChanged etc.
import 'package:dart_libp2p_pubsub/src/core/blacklist.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/multiaddr.dart';

// Assuming we'll use mockito for mocks similar to notify_test.dart
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

// Import the generated mocks file (will be created by build_runner)
// Ensure this path is correct and the file is generated.
// For now, we might need a placeholder or to generate it.
// For peer_gater_test.mocks.dart
@GenerateMocks([
  Host, // Keep MockHost if other parts of PubSub might use it with PeerGater
  Blacklist,
  Conn,
])
import 'peer_gater_test.mocks.dart';

void main() {
  group('SimplePeerGater Tests', () {
    late SimplePeerGater peerGaterWithBlacklist;
    late SimplePeerGater peerGaterWithoutBlacklist;
    late MockBlacklist mockBlacklist;
    late MockConn mockConn;
    late PeerId peerA; // Not blacklisted
    late PeerId peerB; // Blacklisted
    late MultiAddr multiAddrA;

    setUp(() async {
      mockBlacklist = MockBlacklist();
      mockConn = MockConn();
      
      peerA = await PeerId.random();
      peerB = await PeerId.random();
      multiAddrA = MultiAddr('/ip4/127.0.0.1/tcp/1234'); // Corrected MultiAddr instantiation

      // Setup SimplePeerGater instances
      peerGaterWithBlacklist = SimplePeerGater(blacklist: mockBlacklist);
      peerGaterWithoutBlacklist = SimplePeerGater(); // No blacklist

      // Default behavior for blacklist: peerA is not contained, peerB is contained.
      when(mockBlacklist.contains(peerA)).thenReturn(false);
      when(mockBlacklist.contains(peerB)).thenReturn(true);

      // Default behavior for mockConn
      // Let's assume mockConn.remotePeer returns peerA by default for some tests
      when(mockConn.remotePeer).thenReturn(peerA);
    });

    group('interceptPeerDial', () {
      test('should allow dial if peer is not blacklisted (with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptPeerDial(peerA), isTrue);
        verify(mockBlacklist.contains(peerA)).called(1);
      });

      test('should deny dial if peer is blacklisted (with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptPeerDial(peerB), isFalse);
        verify(mockBlacklist.contains(peerB)).called(1);
      });

      test('should allow dial if no blacklist is provided', () {
        expect(peerGaterWithoutBlacklist.interceptPeerDial(peerA), isTrue);
        expect(peerGaterWithoutBlacklist.interceptPeerDial(peerB), isTrue);
      });
    });

    group('interceptAddrDial', () {
      test('should allow dial if peer is not blacklisted (with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptAddrDial(peerA, multiAddrA), isTrue);
        verify(mockBlacklist.contains(peerA)).called(1);
      });

      test('should deny dial if peer is blacklisted (with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptAddrDial(peerB, multiAddrA), isFalse);
        verify(mockBlacklist.contains(peerB)).called(1);
      });

      test('should allow dial if no blacklist is provided', () {
        expect(peerGaterWithoutBlacklist.interceptAddrDial(peerA, multiAddrA), isTrue);
        expect(peerGaterWithoutBlacklist.interceptAddrDial(peerB, multiAddrA), isTrue);
      });
    });

    group('interceptAccept', () {
      test('should allow accept if peer is not blacklisted (with blacklist)', () {
        when(mockConn.remotePeer).thenReturn(peerA);
        expect(peerGaterWithBlacklist.interceptAccept(mockConn), isTrue);
        verify(mockBlacklist.contains(peerA)).called(1);
      });

      test('should deny accept if peer is blacklisted (with blacklist)', () {
        when(mockConn.remotePeer).thenReturn(peerB);
        expect(peerGaterWithBlacklist.interceptAccept(mockConn), isFalse);
        verify(mockBlacklist.contains(peerB)).called(1);
      });

      test('should allow accept if no blacklist is provided', () {
        when(mockConn.remotePeer).thenReturn(peerA); // or peerB, doesn't matter
        expect(peerGaterWithoutBlacklist.interceptAccept(mockConn), isTrue);
      });
    });
    
    group('interceptSecured', () {
      test('should allow secured if peer is not blacklisted (outbound, with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptSecured(peerA, mockConn, true), isTrue);
        verify(mockBlacklist.contains(peerA)).called(1);
      });
       test('should allow secured if peer is not blacklisted (inbound, with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptSecured(peerA, mockConn, false), isTrue);
        verify(mockBlacklist.contains(peerA)).called(1); // called(2) if counting previous
      });


      test('should deny secured if peer is blacklisted (outbound, with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptSecured(peerB, mockConn, true), isFalse);
        verify(mockBlacklist.contains(peerB)).called(1);
      });
      test('should deny secured if peer is blacklisted (inbound, with blacklist)', () {
        expect(peerGaterWithBlacklist.interceptSecured(peerB, mockConn, false), isFalse);
        verify(mockBlacklist.contains(peerB)).called(1); // called(2) if counting previous
      });

      test('should allow secured if no blacklist is provided (outbound)', () {
        expect(peerGaterWithoutBlacklist.interceptSecured(peerA, mockConn, true), isTrue);
      });
       test('should allow secured if no blacklist is provided (inbound)', () {
        expect(peerGaterWithoutBlacklist.interceptSecured(peerB, mockConn, false), isTrue);
      });
    });

    group('interceptUpgraded', () {
      test('should allow upgraded if peer is not blacklisted (with blacklist)', () {
        when(mockConn.remotePeer).thenReturn(peerA);
        final result = peerGaterWithBlacklist.interceptUpgraded(mockConn);
        expect(result.$1, isTrue); // $1 for the first element of the record (bool allow)
        expect(result.$2, isEmpty); // ReasonNoReason is ""
        verify(mockBlacklist.contains(peerA)).called(1);
      });

      test('should deny upgraded if peer is blacklisted (with blacklist)', () {
        when(mockConn.remotePeer).thenReturn(peerB);
        final result = peerGaterWithBlacklist.interceptUpgraded(mockConn);
        expect(result.$1, isFalse);
        expect(result.$2, equals("peer is blacklisted"));
        verify(mockBlacklist.contains(peerB)).called(1);
      });

      test('should allow upgraded if no blacklist is provided', () {
        when(mockConn.remotePeer).thenReturn(peerA);
        final result = peerGaterWithoutBlacklist.interceptUpgraded(mockConn);
        expect(result.$1, isTrue);
        expect(result.$2, isEmpty);
      });
    });
  });
}

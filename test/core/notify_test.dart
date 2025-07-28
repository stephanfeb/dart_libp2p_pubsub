import 'dart:async';
import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/notify.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/host/host.dart';
// crypto_ed25519 and keys are not directly needed for mocks if PeerId is created differently or mocked
// import 'package:dart_libp2p/core/crypto/keys.dart';
// import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_network_context;
import 'package:dart_libp2p/core/event/bus.dart' as event_bus;
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peerstore.dart'; // For Peerstore type
import 'package:dart_libp2p/core/connmgr/conn_manager.dart'; // For ConnManager type
import 'package:dart_libp2p/p2p/protocol/holepunch/holepunch_service.dart'; // For HolePunchService type
import 'package:dart_libp2p/core/protocol/switch.dart'; // For ProtocolSwitch type
import 'package:dart_libp2p/core/network/network.dart' as core_network; // For Network type
import 'package:dart_libp2p/core/interfaces.dart'; // For Connectedness, EvtPeerConnectednessChanged

import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'notify_test.mocks.dart'; // Import for generated mocks

// Generate mocks for Host, EventBus, Emitter, and Subscription
@GenerateMocks([
  Host,
  event_bus.EventBus,
  event_bus.Emitter,
  event_bus.Subscription
])
// All manual mock classes (MockHost, _MockEmitter, _MockEventBus, _MockSubscription, MockEvtPeerConnectednessChanged) are removed.


void main() {
  group('PeerNotifier Tests', () {
    late PeerNotifier notifier;
    late PeerId peerA;
    // These will be instances of the generated Mock classes
    late MockHost mockHost;
    late MockEventBus mockEventBus;
    late MockSubscription mockSubscription; // Mock for event_bus.Subscription
    late StreamController<EvtPeerConnectednessChanged> eventController;

    setUp(() async {
      // Initialize mocks
      mockHost = MockHost();
      mockEventBus = MockEventBus();
      mockSubscription = MockSubscription();
      eventController = StreamController<EvtPeerConnectednessChanged>.broadcast();

      // Stub mockHost.eventBus to return our mockEventBus
      when(mockHost.eventBus).thenReturn(mockEventBus);

      // Stub mockEventBus.subscribe to return our mockSubscription
      // We subscribe to EvtPeerConnectednessChanged specifically in PeerNotifier
      when(mockEventBus.subscribe(EvtPeerConnectednessChanged))
          .thenReturn(mockSubscription);
      
      // Stub mockSubscription.stream to return the stream from our controller
      when(mockSubscription.stream).thenAnswer((_) => eventController.stream);

      // Create PeerNotifier with the mockHost
      notifier = PeerNotifier(mockHost);
      
      // Create a PeerId for testing
      // Using a fixed string PeerId for predictability in tests, or random if preferred.
      // For simplicity with PeerId.random(), ensure it's awaited if it's async.
      // Let's use a fixed one for now to avoid async issues in PeerId creation if not handled.
      // peerA = await PeerId.random(); // If PeerId.random() is async and needed
      peerA = PeerId.fromString('QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N'); // Example PeerId
    });

    tearDown(() {
      notifier.dispose();
      eventController.close();
      // It's good practice to also call close on mockSubscription if it has a close method
      // and if it's not automatically handled by mockito or if it holds resources.
      // For this example, assuming dispose() on notifier handles unsubscription.
    });

    test('onPeerConnected registers callback and it is invoked on connected event', () async {
      final completer = Completer<PeerId>();
      notifier.onPeerConnected((p) {
        if (p == peerA) {
          completer.complete(p);
        }
      });

      // Fire a connected event using the StreamController
      eventController.add(EvtPeerConnectednessChanged(peer: peerA, connectedness: Connectedness.connected));
      
      final notifiedPeer = await completer.future.timeout(Duration(milliseconds: 100));
      expect(notifiedPeer, equals(peerA));
    });

    test('onPeerDisconnected registers callback and it is invoked on disconnected event', () async {
      final completer = Completer<PeerId>();
      notifier.onPeerDisconnected((p) {
         if (p == peerA) {
          completer.complete(p);
        }
      });

      // Fire a disconnected event using the StreamController
      eventController.add(EvtPeerConnectednessChanged(peer: peerA, connectedness: Connectedness.notConnected));

      final notifiedPeer = await completer.future.timeout(Duration(milliseconds: 100));
      expect(notifiedPeer, equals(peerA));
    });
    
    test('dispose clears callbacks and they are not invoked after dispose', () async {
      bool connectedCalled = false;
      bool disconnectedCalled = false;

      notifier.onPeerConnected((p) { connectedCalled = true; });
      notifier.onPeerDisconnected((p) { disconnectedCalled = true; });
      
      notifier.dispose(); // This should cancel the subscription internally

      // Attempt to fire events after dispose
      eventController.add(EvtPeerConnectednessChanged(peer: peerA, connectedness: Connectedness.connected));
      eventController.add(EvtPeerConnectednessChanged(peer: peerA, connectedness: Connectedness.notConnected));

      // Allow some time for async events to potentially propagate if not cleared
      await Future.delayed(Duration(milliseconds: 50)); 

      expect(connectedCalled, isFalse, reason: "Connected callback should not be called after dispose.");
      expect(disconnectedCalled, isFalse, reason: "Disconnected callback should not be called after dispose.");
      
      // Verify that the subscription was cancelled (if PeerNotifier exposes a way or if mockito can verify internal calls)
      // For now, we rely on the functional behavior. If PeerNotifier calls subscription.cancel(),
      // we could verify: verify(mockSubscription.cancel()).called(1);
      // This depends on PeerNotifier's implementation details.
    });
  });
}

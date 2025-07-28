import 'dart:async';

import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/subscription.dart';
// Not importing pubsub_message or PeerId for now as Subscription uses `dynamic` for messages
// and doesn't directly interact with PeerId.

void main() {
  group('Subscription Tests', () {
    const testTopic = 'test-topic';
    late Subscription subscription;
    late Completer<void> cancelCallbackCompleter;

    setUp(() {
      cancelCallbackCompleter = Completer<void>();
      subscription = Subscription(testTopic, () {
        cancelCallbackCompleter.complete();
        return Future.value();
      });
    });

    tearDown(() async {
      // Ensure subscription is cancelled to clean up resources if not done by test
      if (!subscription.isCancelled) {
        await subscription.cancel();
      }
    });

    test('topic getter returns the correct topic name', () {
      expect(subscription.topic, equals(testTopic));
    });

    test('deliver method pushes messages to the stream', () async {
      final message1 = 'hello';
      final message2 = 123;
      
      final receivedMessages = <dynamic>[];
      final subFuture = subscription.stream.listen(receivedMessages.add).asFuture();

      subscription.deliver(message1);
      subscription.deliver(message2);

      // Give a moment for messages to propagate, then close the stream for the test
      await Future.delayed(Duration.zero); // Allow microtasks to run
      await subscription.cancel(); // This will close the stream

      await subFuture; // Wait for the stream listener to complete

      expect(receivedMessages, containsAllInOrder([message1, message2]));
    });

    test('cancel method closes the stream and calls the cancel callback', () async {
      expect(subscription.isCancelled, isFalse);

      final streamDoneCompleter = Completer<void>();
      subscription.stream.listen(
        (_) {}, // We don't care about messages here
        onDone: () {
          streamDoneCompleter.complete();
        },
        onError: (e) {
          streamDoneCompleter.completeError(e);
        }
      );

      await subscription.cancel();

      expect(subscription.isCancelled, isTrue);
      await expectLater(cancelCallbackCompleter.future, completes);
      await expectLater(streamDoneCompleter.future, completes);
    });

    test('deliver does not push messages after cancel', () async {
      final message1 = 'first message';
      final messageIgnored = 'ignored message';
      
      final receivedMessages = <dynamic>[];
      final subFuture = subscription.stream.listen(receivedMessages.add).asFuture();

      subscription.deliver(message1);
      await subscription.cancel(); // Cancel before delivering the second message
      
      // This should not throw an error, but the message should not be delivered
      subscription.deliver(messageIgnored); 

      await subFuture; // Wait for stream to close

      expect(receivedMessages, equals([message1]));
      expect(receivedMessages, isNot(contains(messageIgnored)));
    });

    test('isCancelled getter reflects stream state', () async {
      expect(subscription.isCancelled, isFalse);
      await subscription.cancel();
      expect(subscription.isCancelled, isTrue);
    });

    test('multiple listeners on broadcast stream receive messages', () async {
      final message = 'broadcast test';
      final completer1 = Completer<dynamic>();
      final completer2 = Completer<dynamic>();

      subscription.stream.listen(completer1.complete);
      subscription.stream.listen(completer2.complete);

      subscription.deliver(message);

      final results = await Future.wait([
        completer1.future.timeout(Duration(milliseconds: 50)),
        completer2.future.timeout(Duration(milliseconds: 50)),
      ]);

      expect(results[0], equals(message));
      expect(results[1], equals(message));
      
      await subscription.cancel();
    });

    test('cancel is idempotent and calls callback only once', () async {
      int cancelCallbackCount = 0;
      // Create a new subscription instance specifically for this test
      // to control the callback and its count.
      final subForIdempotencyTest = Subscription(testTopic, () {
        cancelCallbackCount++;
        return Future.value();
      });

      expect(subForIdempotencyTest.isCancelled, isFalse);
      expect(cancelCallbackCount, 0);

      // First cancel
      await subForIdempotencyTest.cancel();
      expect(subForIdempotencyTest.isCancelled, isTrue);
      expect(cancelCallbackCount, 1, reason: "Callback should be called once on the first cancel.");

      // Second cancel
      await subForIdempotencyTest.cancel();
      expect(subForIdempotencyTest.isCancelled, isTrue, reason: "Subscription should remain cancelled.");
      expect(cancelCallbackCount, 1, reason: "Callback should not be called again on subsequent cancels.");
      
      // Third cancel (just to be sure)
      await subForIdempotencyTest.cancel();
      expect(subForIdempotencyTest.isCancelled, isTrue);
      expect(cancelCallbackCount, 1);
    });
  });
}

import 'package:dart_libp2p_pubsub/src/util/timecache.dart';
import 'package:test/test.dart';

void main() {
  late Duration now;
  Duration clock() => now;
  const ttl = Duration(minutes: 2);

  setUp(() => now = Duration.zero);

  group('FirstSeenCache, as go-libp2p-pubsub', () {
    test('a key expires its TTL after it was first seen, however often it is seen again', () {
      final cache = TimeCache<String>(ttl, clock: clock);
      expect(cache, isA<FirstSeenCache<String>>());
      expect(cache.add('a'), isTrue);
      now = const Duration(minutes: 1);
      expect(cache.add('a'), isFalse);
      expect(cache.contains('a'), isTrue);
      now = const Duration(minutes: 2);
      expect(cache.contains('a'), isFalse);
      expect(cache.add('a'), isTrue, reason: 'expired, so new again');
    });

    test('has no size limit', () {
      final cache = FirstSeenCache<int>(ttl, clock: clock);
      for (var i = 0; i < 200000; i++) {
        cache.add(i);
      }
      expect(cache.length, 200000);
      expect(cache.contains(0), isTrue);
    });

    test('removes expired keys as keys are added', () {
      final cache = FirstSeenCache<int>(ttl, clock: clock);
      for (var i = 0; i < 100; i++) {
        cache.add(i);
      }
      now = const Duration(minutes: 1);
      cache.add(100);
      expect(cache.length, 101);
      now = const Duration(minutes: 2);
      cache.add(101);
      expect(cache.length, 2);
    });
  });

  group('LastSeenCache, as go-libp2p-pubsub', () {
    test('a key expires its TTL after it was last added or found', () {
      final cache = TimeCache<String>(ttl, strategy: SeenMessagesStrategy.lastSeen, clock: clock);
      expect(cache, isA<LastSeenCache<String>>());
      expect(cache.add('a'), isTrue);
      now = const Duration(minutes: 1, seconds: 30);
      expect(cache.add('a'), isFalse, reason: 'seen again: its TTL starts again');
      now = const Duration(minutes: 3);
      expect(cache.contains('a'), isTrue, reason: 'found: its TTL starts again');
      now = const Duration(minutes: 4, seconds: 59);
      expect(cache.contains('a'), isTrue);
      now = const Duration(minutes: 7);
      expect(cache.contains('a'), isFalse);
      expect(cache.add('a'), isTrue);
    });

    test('removes expired keys as keys are added, in the order they were last seen', () {
      final cache = LastSeenCache<String>(ttl, clock: clock);
      cache.add('a');
      cache.add('b');
      now = const Duration(minutes: 1);
      cache.contains('a'); // a now expires after b.
      now = const Duration(minutes: 2, seconds: 30);
      cache.add('c');
      expect(cache.length, 2);
      expect(cache.contains('a'), isTrue);
      expect(cache.contains('b'), isFalse);
    });
  });

  test('the default clock is monotonic and advances', () async {
    final before = monotonicNow();
    await Future.delayed(const Duration(milliseconds: 10));
    expect(monotonicNow() - before, greaterThanOrEqualTo(const Duration(milliseconds: 10)));
  });
}

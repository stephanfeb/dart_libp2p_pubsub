import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/util/backoff.dart';
import 'dart:math';

void main() {
  group('ExponentialBackoff Tests', () {
    test('should generate increasing delays (on average with jitter)', () {
      const minDelay = Duration(milliseconds: 100);
      const maxDelayConfig = Duration(seconds: 5);
      const factorConfig = 2.0;
      const jitterConfig = 0.1; // 10% jitter

      final backoff = ExponentialBackoff(
        minDelay: minDelay,
        maxDelay: maxDelayConfig,
        factor: factorConfig,
        jitter: jitterConfig,
      );

      Duration previousDelay = Duration.zero;
      int increaseCount = 0;
      int decreaseDueToJitterCount = 0;

      for (int i = 0; i < 20; i++) { // More iterations to observe trend
        final delay = backoff.next();
        
        if (i > 0) {
          if (delay > previousDelay) {
            increaseCount++;
          } else if (delay < previousDelay && previousDelay < maxDelayConfig) {
            // This can happen due to jitter.
            // The base delay for `_currentDelay` still increases, but jitter might make the output smaller.
            decreaseDueToJitterCount++;
          }
        }
        expect(delay, lessThanOrEqualTo(maxDelayConfig));
        // The very first delay can be less than minDelay if minDelay itself is jittered down.
        // The internal _calculateDelayWithJitter ensures it's not < 0.
        // And not less than minDelay if attempts > 0.
        if (backoff.attempts > 1) { // After the first call, it should be >= minDelay (post-jitter)
             expect(delay.inMilliseconds, greaterThanOrEqualTo( (minDelay.inMilliseconds * (1-jitterConfig*0.5)).floor() ));
        }

        previousDelay = delay;
        // print('Attempt ${backoff.attempts}: Delay = ${delay.inMilliseconds}ms');
      }
      // Expect that, on average, delays increase more often than they decrease due to jitter
      expect(increaseCount, greaterThan(decreaseDueToJitterCount + 5), reason: "Delays should generally trend upwards.");
    });

    test('delay should not exceed maxDelay', () {
      const min = Duration(milliseconds: 100);
      const max = Duration(milliseconds: 500);
      const factorVal = 2.0;

      final backoff = ExponentialBackoff(
        minDelay: min,
        maxDelay: max,
        factor: factorVal,
        jitter: 0.0, // No jitter for precise testing of max
      );

      Duration delay = Duration.zero;
      for (int i = 0; i < 10; i++) { // Enough attempts to hit max
        delay = backoff.next();
        expect(delay, lessThanOrEqualTo(max));
      }
      // After enough iterations, it should consistently be at maxDelay
      expect(delay, equals(max));
    });

    test('reset should bring delay back towards minDelay', () {
      const min = Duration(milliseconds: 50);
      const factorVal = 2.0;

      final backoff = ExponentialBackoff(
        minDelay: min,
        maxDelay: Duration(seconds: 1),
        factor: factorVal,
        jitter: 0.0, // No jitter for precise testing
      );

      // Run a few times to increase delay
      backoff.next();
      backoff.next();
      final delayAfterIncreases = backoff.next();
      // currentDelay inside backoff is now min * factor * factor = 50 * 2 * 2 = 200ms
      // next() returns this _currentDelay (200ms) then updates _currentDelay for the *next* call.
      expect(delayAfterIncreases, equals(Duration(milliseconds: (min.inMilliseconds * factorVal * factorVal).round())));

      backoff.reset();
      final delayAfterReset = backoff.next();
      // After reset, _currentDelay is minDelay. next() returns this.
      expect(delayAfterReset, equals(min));
    });

    test('jitter should introduce randomness within expected bounds (for first call)', () {
      const min = Duration(milliseconds: 100);
      const factorVal = 2.0;
      const jitterVal = 0.5; // 50% jitter

      final backoff = ExponentialBackoff(
        minDelay: min,
        maxDelay: Duration(seconds: 10),
        factor: factorVal,
        jitter: jitterVal,
      );

      // For the first call to next(), _currentDelay is minDelay.
      // _calculateDelayWithJitter uses this _currentDelay as base.
      // Jitter range is baseDelayMs * _jitter. Jitter is +/- half of this range.
      // So, actual jitter amount is between -(baseDelayMs * _jitter / 2) and +(baseDelayMs * _jitter / 2)
      final baseDelayMs = min.inMilliseconds;
      final halfJitterRange = baseDelayMs * jitterVal / 2.0;
      final minExpectedMs = baseDelayMs - halfJitterRange;
      final maxExpectedMs = baseDelayMs + halfJitterRange;
      
      bool sawVariationComparedToMean = false;
      Duration firstDelayValue = Duration.zero;

      for (int i = 0; i < 30; i++) { // Multiple samples
        backoff.reset(); // Reset to test jitter around minDelay consistently
        final delay = backoff.next();
        
        expect(delay.inMilliseconds, greaterThanOrEqualTo(minExpectedMs.floor()), reason: "Delay ${delay.inMilliseconds}ms was less than min expected ${minExpectedMs.floor()}ms");
        expect(delay.inMilliseconds, lessThanOrEqualTo(maxExpectedMs.ceil()), reason: "Delay ${delay.inMilliseconds}ms was greater than max expected ${maxExpectedMs.ceil()}ms");

        if (i == 0) {
          firstDelayValue = delay;
        } else {
          // Check if any subsequent delay is different from the first one observed.
          // This is a simple way to check for variation.
          if (delay.inMilliseconds != firstDelayValue.inMilliseconds) {
            sawVariationComparedToMean = true;
          }
        }
      }
      expect(sawVariationComparedToMean, isTrue, reason: "Expected to see variation in delays due to jitter.");
    });
    
    test('factor should correctly scale the delay (no jitter)', () {
      const min = Duration(milliseconds: 100);
      const factorVal = 3.0;
      final backoff = ExponentialBackoff(
        minDelay: min,
        maxDelay: Duration(seconds: 10),
        factor: factorVal,
        jitter: 0.0, // No jitter
      );

      // 1st call: returns _minDelay (100ms). _currentDelay becomes 100*3 = 300ms.
      var delay1 = backoff.next();
      expect(delay1, equals(min));

      // 2nd call: returns _currentDelay (300ms). _currentDelay becomes 300*3 = 900ms.
      var delay2 = backoff.next();
      expect(delay2, equals(Duration(milliseconds: (min.inMilliseconds * factorVal).round())));
      
      // 3rd call: returns _currentDelay (900ms). _currentDelay becomes 900*3 = 2700ms.
      var delay3 = backoff.next();
      expect(delay3, equals(Duration(milliseconds: (min.inMilliseconds * factorVal * factorVal).round())));
    });

  });
}

import 'dart:async';
import 'dart:math'; // For Random and min/max

/// Defines a factory for creating Backoff timers.
abstract class BackoffFactory {
  /// Returns a new Backoff timer.
  Backoff create();
}

/// Defines an interface for a Backoff timer.
abstract class Backoff {
  /// Returns the duration of the next backoff.
  Duration next();

  /// Resets the backoff timer.
  void reset();
}

/// Implements an exponential backoff strategy with jitter.
class ExponentialBackoff implements Backoff {
  final Duration _minDelay;
  final Duration _maxDelay;
  final double _factor;
  final double _jitter; // Jitter factor (0.0 to 1.0)
  final Random _random;

  Duration _currentDelay;
  int _attempts = 0;

  ExponentialBackoff({
    required Duration minDelay,
    required Duration maxDelay,
    double factor = 2.0, // Standard exponential factor
    double jitter = 0.1, // 10% jitter by default
    Random? random,
  })  : _minDelay = minDelay,
        _maxDelay = maxDelay,
        _factor = factor,
        _jitter = jitter.clamp(0.0, 1.0), // Ensure jitter is between 0 and 1
        _random = random ?? Random(),
        _currentDelay = minDelay;

  @override
  Duration next() {
    final delayWithJitter = _calculateDelayWithJitter(_currentDelay);
    
    // Increase current delay for next attempt, capped by maxDelay
    if (_currentDelay < _maxDelay) {
      var nextBaseDelayMs = _currentDelay.inMilliseconds * _factor;
      _currentDelay = Duration(milliseconds: nextBaseDelayMs.round());
      if (_currentDelay > _maxDelay) {
        _currentDelay = _maxDelay;
      }
    }
    _attempts++;
    return delayWithJitter;
  }

  Duration _calculateDelayWithJitter(Duration baseDelay) {
    if (_jitter == 0.0) {
      return baseDelay;
    }
    final jitterRange = baseDelay.inMilliseconds * _jitter;
    // Jitter can be +/- half of the jitterRange
    final minJitter = -jitterRange / 2;
    final maxJitter = jitterRange / 2;
    final randomJitterMs = minJitter + _random.nextDouble() * (maxJitter - minJitter);
    
    var finalDelayMs = baseDelay.inMilliseconds + randomJitterMs;
    
    // Ensure delay is not less than minDelay (unless it's the very first attempt and minDelay is 0)
    // and not more than maxDelay.
    if (_attempts > 0 && finalDelayMs < _minDelay.inMilliseconds) {
      finalDelayMs = _minDelay.inMilliseconds.toDouble();
    }
    if (finalDelayMs > _maxDelay.inMilliseconds) {
      finalDelayMs = _maxDelay.inMilliseconds.toDouble();
    }
    // Also ensure it's not negative if minDelay is very small or zero.
    if (finalDelayMs < 0) finalDelayMs = 0;

    return Duration(milliseconds: finalDelayMs.round());
  }

  @override
  void reset() {
    _currentDelay = _minDelay;
    _attempts = 0;
  }

  int get attempts => _attempts;
}

/// A BackoffFactory that creates ExponentialBackoff timers.
class ExponentialBackoffFactory implements BackoffFactory {
  final Duration minDelay;
  final Duration maxDelay;
  final double factor;
  final double jitter;
  final Random? random; // Optional shared random instance

  ExponentialBackoffFactory({
    required this.minDelay,
    required this.maxDelay,
    this.factor = 2.0,
    this.jitter = 0.1,
    this.random,
  });

  @override
  Backoff create() {
    return ExponentialBackoff(
      minDelay: minDelay,
      maxDelay: maxDelay,
      factor: factor,
      jitter: jitter,
      random: random ?? Random(), // Create new Random if none provided
    );
  }
}

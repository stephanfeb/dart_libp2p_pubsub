import 'dart:collection';

/// How long a seen message ID is remembered, as go-libp2p-pubsub's
/// `TimeCacheStrategy` (`WithSeenMessagesStrategy`).
enum SeenMessagesStrategy {
  /// An ID expires its TTL after it was first seen (Go's default).
  firstSeen,

  /// An ID expires its TTL after it was last seen: each time it is seen
  /// again, its TTL starts again.
  lastSeen,
}

/// A monotonic clock: the time since some fixed point, unaffected by
/// changes to the wall clock.
typedef MonotonicClock = Duration Function();

final Stopwatch _stopwatch = Stopwatch()..start();

/// The default [MonotonicClock].
Duration monotonicNow() => _stopwatch.elapsed;

/// A set of keys that each expire after a TTL, as go-libp2p-pubsub's
/// `timecache.TimeCache`. It has no size limit, as Go's: it holds the keys
/// seen in the last TTL. Expired keys are removed as keys are added.
///
/// Time is read from a monotonic clock, so a change to the wall clock does
/// not expire keys early or keep them too long.
abstract class TimeCache<K> {
  final Duration _ttl;
  final MonotonicClock _clock;

  /// The expiry of each key, in the order of their expiries.
  final LinkedHashMap<K, Duration> _expiries = LinkedHashMap<K, Duration>();

  TimeCache._(this._ttl, MonotonicClock? clock) : _clock = clock ?? monotonicNow;

  /// A cache whose keys expire [ttl] after they were first seen, or last
  /// seen, as [strategy] says.
  factory TimeCache(Duration ttl, {SeenMessagesStrategy strategy = SeenMessagesStrategy.firstSeen, MonotonicClock? clock}) =>
      switch (strategy) {
        SeenMessagesStrategy.firstSeen => FirstSeenCache<K>(ttl, clock: clock),
        SeenMessagesStrategy.lastSeen => LastSeenCache<K>(ttl, clock: clock),
      };

  /// Adds [key]. Returns whether it was not in the cache.
  bool add(K key);

  /// Whether [key] is in the cache.
  bool contains(K key);

  bool _expired(K key, Duration now) {
    final expiry = _expiries[key];
    if (expiry == null) return true;
    if (expiry > now) return false;
    _expiries.remove(key);
    return true;
  }

  /// Removes the expired keys. They come first, as the keys are kept in the
  /// order of their expiries.
  void _sweep(Duration now) {
    while (_expiries.isNotEmpty) {
      final oldest = _expiries.keys.first;
      if (_expiries[oldest]! > now) break;
      _expiries.remove(oldest);
    }
  }

  /// Sets the expiry of [key] to [now] plus the TTL, the latest of all.
  void _touch(K key, Duration now) {
    _expiries.remove(key);
    _expiries[key] = now + _ttl;
  }

  /// The number of keys, expired ones not yet removed included.
  int get length => _expiries.length;

  /// Removes all keys.
  void clear() => _expiries.clear();

  /// Removes all keys. The cache can still be used.
  void dispose() => clear();
}

/// A [TimeCache] whose keys expire their TTL after they were first seen, as
/// go-libp2p-pubsub's `FirstSeenCache`.
class FirstSeenCache<K> extends TimeCache<K> {
  FirstSeenCache(Duration ttl, {MonotonicClock? clock}) : super._(ttl, clock);

  @override
  bool add(K key) {
    final now = _clock();
    _sweep(now);
    if (!_expired(key, now)) return false;
    _touch(key, now);
    return true;
  }

  @override
  bool contains(K key) => !_expired(key, _clock());
}

/// A [TimeCache] whose keys expire their TTL after they were last seen, as
/// go-libp2p-pubsub's `LastSeenCache`: adding a key, or finding it with
/// [contains], starts its TTL again.
class LastSeenCache<K> extends TimeCache<K> {
  LastSeenCache(Duration ttl, {MonotonicClock? clock}) : super._(ttl, clock);

  @override
  bool add(K key) {
    final now = _clock();
    _sweep(now);
    final added = _expired(key, now);
    _touch(key, now);
    return added;
  }

  @override
  bool contains(K key) {
    final now = _clock();
    if (_expired(key, now)) return false;
    _touch(key, now);
    return true;
  }
}

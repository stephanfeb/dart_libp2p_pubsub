import 'dart:async';
import 'dart:collection'; // For LinkedHashMap
import 'dart:math'; // For Random

/// A cache that stores the first time a key was seen, with a TTL.
///
/// Entries are evicted when their TTL expires or randomly if the cache exceeds
/// its capacity (though random eviction is a simplified approach here compared
/// to go-libp2p-pubsub's RandomExpireCache which has more specific logic).
class FirstSeenCache<K> {
  final Duration _ttl;
  final int _capacity;
  final LinkedHashMap<K, DateTime> _entries = LinkedHashMap<K, DateTime>();
  Timer? _gcTimer;
  final Random _random = Random();

  /// Creates a new [FirstSeenCache].
  ///
  /// [_ttl] is the time-to-live for entries.
  /// [_capacity] is the maximum number of entries the cache can hold.
  /// [gcInterval] is the interval for periodic garbage collection of expired entries.
  /// If null, GC only happens on access or when adding new entries if capacity is hit.
  FirstSeenCache(this._ttl, this._capacity, {Duration? gcInterval}) {
    if (gcInterval != null && gcInterval.inMilliseconds > 0) {
      _gcTimer = Timer.periodic(gcInterval, (_) => _gc());
    }
  }

  /// Adds a key to the cache if it's not already present.
  ///
  /// Returns `true` if the key was added (i.e., it was the first time it was seen
  /// or its previous entry expired), `false` otherwise.
  /// If the key was already present and not expired, its timestamp is NOT updated.
  bool add(K key) {
    final now = DateTime.now();
    final existingEntryTime = _entries[key];

    if (existingEntryTime != null) {
      if (now.difference(existingEntryTime) <= _ttl) {
        return false; // Still valid, not adding again
      } else {
        // Expired, remove to re-add with new timestamp
        _entries.remove(key);
      }
    }

    // Ensure capacity before adding
    _ensureCapacity();

    _entries[key] = now;
    return true;
  }

  /// Checks if a key is present in the cache and has not expired.
  bool contains(K key) {
    final entryTime = _entries[key];
    if (entryTime == null) {
      return false;
    }
    if (DateTime.now().difference(entryTime) > _ttl) {
      _entries.remove(key); // Eagerly remove expired on access
      return false;
    }
    return true;
  }

  /// Removes expired entries from the cache.
  void _gc() {
    final now = DateTime.now();
    final List<K> toRemove = [];
    _entries.forEach((key, timestamp) {
      if (now.difference(timestamp) > _ttl) {
        toRemove.add(key);
      }
    });
    for (final key in toRemove) {
      _entries.remove(key);
    }
  }

  /// Ensures the cache does not exceed its capacity.
  /// If over capacity, removes entries (currently oldest, could be random).
  void _ensureCapacity() {
    // Perform a GC pass first to clear out expired items
    _gc();

    // If still over capacity, remove oldest items (LinkedHashMap preserves insertion order)
    // Go's RandomExpireCache removes random entries. For simplicity, we do LRU-like here.
    while (_entries.length >= _capacity && _capacity > 0) { // Check >= because we are about to add one
      if (_entries.isEmpty) break;
      final keyToRemove = _entries.keys.first;
      _entries.remove(keyToRemove);
      // print('FirstSeenCache: Evicted $keyToRemove due to capacity limit.');
    }
  }

  /// Clears all entries from the cache.
  void clear() {
    _entries.clear();
  }

  /// Disposes of the cache, stopping any timers.
  void dispose() {
    _gcTimer?.cancel();
    _gcTimer = null;
    clear();
  }

  int get length => _entries.length;
}

// TODO: Implement LastSeenCache if needed. (Now implemented below)
// It would be similar but `add` would update the timestamp if the key exists.

/// A cache that stores the last time a key was seen, with a TTL.
///
/// Entries are evicted when their TTL expires or when the cache exceeds
/// its capacity (evicting the oldest entry).
class LastSeenCache<K> {
  final Duration _ttl;
  final int _capacity;
  final LinkedHashMap<K, DateTime> _entries = LinkedHashMap<K, DateTime>();
  Timer? _gcTimer;

  /// Creates a new [LastSeenCache].
  ///
  /// [_ttl] is the time-to-live for entries.
  /// [_capacity] is the maximum number of entries the cache can hold.
  /// [gcInterval] is the interval for periodic garbage collection of expired entries.
  /// If null, GC only happens on access or when adding new entries if capacity is hit.
  LastSeenCache(this._ttl, this._capacity, {Duration? gcInterval}) {
    if (gcInterval != null && gcInterval.inMilliseconds > 0) {
      _gcTimer = Timer.periodic(gcInterval, (_) => _gc());
    }
  }

  /// Adds or updates a key in the cache with the current timestamp.
  ///
  /// If the key already exists, its timestamp is updated to now, and it's
  /// moved to the end of the LinkedHashMap (most recently seen).
  void add(K key) {
    final now = DateTime.now();

    // If key exists, remove it first to re-add and update its position (most recent)
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    }

    // Ensure capacity before adding
    _ensureCapacity();

    _entries[key] = now;
  }

  /// Checks if a key is present in the cache and has not expired.
  bool contains(K key) {
    final entryTime = _entries[key];
    if (entryTime == null) {
      return false;
    }
    if (DateTime.now().difference(entryTime) > _ttl) {
      _entries.remove(key); // Eagerly remove expired on access
      return false;
    }
    return true;
  }

  /// Gets the timestamp for a key if it's present and not expired.
  /// Returns null otherwise.
  DateTime? get(K key) {
    final entryTime = _entries[key];
    if (entryTime == null) {
      return null;
    }
    if (DateTime.now().difference(entryTime) > _ttl) {
      _entries.remove(key); // Eagerly remove expired on access
      return null;
    }
    return entryTime;
  }
  
  /// Removes expired entries from the cache.
  void _gc() {
    final now = DateTime.now();
    final List<K> toRemove = [];
    _entries.forEach((key, timestamp) {
      if (now.difference(timestamp) > _ttl) {
        toRemove.add(key);
      }
    });
    for (final key in toRemove) {
      _entries.remove(key);
    }
  }

  /// Ensures the cache does not exceed its capacity.
  /// If over capacity, removes the oldest entries.
  void _ensureCapacity() {
    // Perform a GC pass first to clear out expired items
    _gc();

    // If still over capacity, remove oldest items (LinkedHashMap preserves insertion order)
    while (_entries.length >= _capacity && _capacity > 0) {
      if (_entries.isEmpty) break;
      final keyToRemove = _entries.keys.first;
      _entries.remove(keyToRemove);
      // print('LastSeenCache: Evicted $keyToRemove due to capacity limit.');
    }
  }

  /// Clears all entries from the cache.
  void clear() {
    _entries.clear();
  }

  /// Disposes of the cache, stopping any timers.
  void dispose() {
    _gcTimer?.cancel();
    _gcTimer = null;
    clear();
  }

  int get length => _entries.length;
}

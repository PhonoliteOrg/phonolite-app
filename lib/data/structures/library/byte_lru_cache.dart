/// Retained entries are charged for their keys, values and entry overhead.
/// Oversized entries are returned to callers without being retained.
class ByteLruCache<K, V> {
  final int maxBytes;
  final int maxEntries;
  final int Function(K, V) sizeOf;
  final Map<K, ({V value, int bytes})> _entries = <K, ({V value, int bytes})>{};
  int _bytes = 0;

  ByteLruCache({required this.maxBytes, required this.maxEntries, required this.sizeOf})
    : assert(maxBytes > 0),
      assert(maxEntries > 0);

  int get bytes => _bytes;

  int get length => _entries.length;

  Iterable<K> get keys => List<K>.unmodifiable(_entries.keys);

  V? get(K key) {
    final entry = _entries.remove(key);

    if (entry == null) {
      return null;
    }

    _entries[key] = entry;

    return entry.value;
  }

  void put(K key, V value) {
    remove(key);
    final bytes = sizeOf(key, value);

    if (bytes < 0 || bytes > maxBytes) {
      return;
    }

    while (_entries.isNotEmpty && (_entries.length >= maxEntries || _bytes + bytes > maxBytes)) {
      remove(_entries.keys.first);
    }

    _entries[key] = (value: value, bytes: bytes);
    _bytes += bytes;
  }

  void remove(K key) {
    final removed = _entries.remove(key);

    if (removed != null) {
      _bytes -= removed.bytes;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

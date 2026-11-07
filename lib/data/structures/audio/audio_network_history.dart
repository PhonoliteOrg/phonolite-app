/// Bounded, short-lived network observations shared by one audio worker's sources.
class AudioNetworkHistory {
  static const maximumEntries = 16;
  static const lifetime = Duration(minutes: 5);

  final Duration Function() _now;
  final Map<String, ({int level, Duration updated})> _entries = {};

  AudioNetworkHistory({Duration Function()? now}) : _now = now ?? _monotonicClock();

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  int levelFor(String endpoint) {
    final entry = _entries[endpoint];
    if (entry == null) return 0;

    if (_now() - entry.updated >= lifetime) {
      _entries.remove(endpoint);
      return 0;
    }

    return entry.level;
  }

  void remember(String endpoint, int level) {
    _entries.remove(endpoint);
    _entries[endpoint] = (level: level.clamp(0, 2), updated: _now());
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

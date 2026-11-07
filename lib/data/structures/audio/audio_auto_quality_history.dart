import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef AudioAutoQualityScope = ({String endpoint, String credential, int routeGeneration});

/// Recent Original success and pressure belong to a listener and network route.
/// Each new file must still prove its own reserve and useful delivery rate.
class AudioAutoQualityHistory {
  static const maximumEntries = 16;
  static const lifetime = Duration(minutes: 5);
  static const retryDelay = Duration(seconds: 30);

  final Duration Function() _now;
  final Map<AudioAutoQualityScope, ({bool original, Duration updated, Duration retryAt})> _entries = {};

  AudioAutoQualityHistory({Duration Function()? now}) : _now = now ?? _monotonicClock();

  static AudioAutoQualityScope scope({
    required String endpoint,
    required String token,
    required String serverPin,
    required int routeGeneration,
  }) => (
    endpoint: endpoint,
    credential: sha256.convert(utf8.encode(jsonEncode([token, serverPin]))).toString(),
    routeGeneration: routeGeneration,
  );

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();

    return () => clock.elapsed;
  }

  bool mayWarmOriginal(AudioAutoQualityScope scope) {
    final entry = _recent(scope);

    return entry != null && entry.original && _now() >= entry.retryAt;
  }

  bool mayProbeOriginal(AudioAutoQualityScope scope) {
    final entry = _recent(scope);

    return entry == null || _now() >= entry.retryAt;
  }

  void rememberOriginal(AudioAutoQualityScope scope) {
    if (!mayProbeOriginal(scope)) {
      return;
    }

    _remember(scope, original: true, retryAt: Duration.zero);
  }

  void deferOriginal(AudioAutoQualityScope scope) => _remember(scope, original: false, retryAt: _now() + retryDelay);

  ({bool original, Duration updated, Duration retryAt})? _recent(AudioAutoQualityScope scope) {
    final entry = _entries[scope];

    if (entry != null && _now() - entry.updated >= lifetime) {
      _entries.remove(scope);

      return null;
    }

    return entry;
  }

  void _remember(AudioAutoQualityScope scope, {required bool original, required Duration retryAt}) {
    _entries.remove(scope);
    _entries[scope] = (original: original, updated: _now(), retryAt: retryAt);

    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

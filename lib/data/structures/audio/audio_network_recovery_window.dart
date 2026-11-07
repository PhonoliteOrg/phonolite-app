/// Requires sustained playable delivery before relaxing network buffer protection.
class AudioNetworkRecoveryWindow {
  int? _level;
  Duration? _since;
  int _acceptedThroughMs = 0;
  int _bufferedMs = 0;
  bool _readAheadSatisfied = false;

  void reset() {
    _level = null;
    _since = null;
  }

  bool observe({
    required Duration now,
    required int level,
    required int? rttMs,
    required int bufferedMs,
    required int minimumReserveMs,
    required int acceptedThroughMs,
    required bool readAheadSatisfied,
    required bool userPaused,
  }) {
    final maximumRttMs = level == 2 ? 300 : 160;
    if (level <= 0 || userPaused || rttMs == null || rttMs > maximumRttMs || bufferedMs < minimumReserveMs) {
      reset();

      return false;
    }

    if (_level != level || _since == null || acceptedThroughMs < _acceptedThroughMs || now < _since!) {
      _begin(now, level, bufferedMs, acceptedThroughMs, readAheadSatisfied);

      return false;
    }

    final elapsedMs = (now - _since!).inMilliseconds;
    final requiredMs = level == 2 ? 3000 : 5000;
    if (elapsedMs < requiredMs) {
      return false;
    }

    final deliveredMs = acceptedThroughMs - _acceptedThroughMs;
    final sustainable = deliveredMs * 100 >= elapsedMs * 95;
    // A full bounded queue intentionally stops delivery. Do not require bytes
    // that the receiver has stopped requesting, or mistake a draining cache for
    // a healthy connection.
    final satisfied = _readAheadSatisfied && readAheadSatisfied && bufferedMs >= _bufferedMs - 250;
    if (sustainable || satisfied) {
      reset();

      return true;
    }

    _begin(now, level, bufferedMs, acceptedThroughMs, readAheadSatisfied);

    return false;
  }

  void _begin(Duration now, int level, int bufferedMs, int acceptedThroughMs, bool readAheadSatisfied) {
    _level = level;
    _since = now;
    _bufferedMs = bufferedMs;
    _acceptedThroughMs = acceptedThroughMs;
    _readAheadSatisfied = readAheadSatisfied;
  }
}

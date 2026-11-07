/// Auto's Original gate uses useful decoded delivery and media reserve. RTT,
/// network type and individual lost packets never disqualify a usable source.
class AutoOriginalPolicy {
  static const int targetReserveMs = 8000;
  static const int upgradeReserveMs = 4000;
  static const int fallbackReserveMs = 2000;
  static const Duration retryDelay = Duration(seconds: 30);

  Duration? _healthySince;
  Duration _retryAt = Duration.zero;
  bool _original = false;

  bool get original => _original;

  bool mayPrepare({required Duration now, required int fallbackReserveMs, required bool active}) {
    if (!active || fallbackReserveMs < 6000 || now < _retryAt) {
      _healthySince = null;
      return false;
    }

    final since = _healthySince ??= now;

    return now - since >= const Duration(seconds: 2);
  }

  bool select({
    required Duration now,
    required int reserveMs,
    required double deliveryRatio,
    required bool failed,
    required bool complete,
  }) {
    if (_original) {
      if (failed || (!complete && reserveMs < fallbackReserveMs) || reserveMs <= 0) {
        retire(now);
      }
    } else if (!failed && now >= _retryAt && reserveMs >= upgradeReserveMs && deliveryRatio >= 1.15) {
      _original = true;
    }

    return _original;
  }

  void retire(Duration now) {
    _original = false;
    _healthySince = null;
    _retryAt = now + retryDelay;
  }

  void reset() {
    _original = false;
    _healthySince = null;
    _retryAt = Duration.zero;
  }
}

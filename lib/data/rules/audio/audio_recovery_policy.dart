/// Bounds a source repair episode independently of individual socket attempts.
class AudioRecoveryPolicy {
  static const budget = Duration(seconds: 30);
  static const maximumAttempts = 3;
  static const healthyPeriod = Duration(seconds: 2);

  const AudioRecoveryPolicy();

  Duration stallTimeout({required int playableMilliseconds, int? rttMilliseconds}) {
    final minimum = playableMilliseconds <= 4000 ? 5000 : 8000;

    return Duration(milliseconds: (6 * (rttMilliseconds ?? 0)).clamp(minimum, 12000));
  }

  int healthyReserveMilliseconds(int refillTargetMilliseconds) => refillTargetMilliseconds.clamp(500, 2000);

  Duration retryDelay(int attempts) => switch (attempts) {
    0 => Duration.zero,
    1 => const Duration(seconds: 1),
    _ => const Duration(seconds: 2),
  };
}

/// A monotonic clock can be injected without opening a transport or device.
class AudioRecoveryEpisode {
  final Duration Function() now;
  Duration? _started;
  Duration? _healthySince;
  int _attempts = 0;
  int _checkpoint = 0;

  AudioRecoveryEpisode({required this.now});

  bool get active => _started != null;
  int get attempts => _attempts;
  Duration get remaining {
    final start = _started;
    if (start == null) {
      return AudioRecoveryPolicy.budget;
    }
    final left = AudioRecoveryPolicy.budget - (now() - start);
    return left.isNegative ? Duration.zero : left;
  }

  void begin(int checkpoint) {
    if (active) {
      return;
    }
    _started = now();
    _checkpoint = checkpoint;
    _attempts = 0;
    _healthySince = null;
  }

  bool reserveAttempt() {
    if (!active || remaining == Duration.zero || _attempts >= AudioRecoveryPolicy.maximumAttempts) {
      return false;
    }
    _attempts++;
    _healthySince = null;
    return true;
  }

  void interrupted() => _healthySince = null;

  void observe({
    required int acceptedThrough,
    required int playableMilliseconds,
    int requiredReserveMilliseconds = 2000,
    bool endOfTrack = false,
  }) {
    if (!active || acceptedThrough <= _checkpoint) {
      return;
    }
    if (endOfTrack) {
      reset();
      return;
    }
    if (playableMilliseconds < requiredReserveMilliseconds) {
      _healthySince = null;
      return;
    }
    _healthySince ??= now();
    if (now() - _healthySince! >= AudioRecoveryPolicy.healthyPeriod) {
      reset();
    }
  }

  void reset() {
    _started = null;
    _healthySince = null;
    _attempts = 0;
  }
}

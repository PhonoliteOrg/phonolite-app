import 'package:phonolite_app/data/rules/audio/audio_recovery_policy.dart';

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

part of '../audio_engine.dart';

/// Bounds a period of demanded work without treating intentional backpressure
/// or a user pause as failure. The clock is monotonic and starts with demand.
class _AudioProgressDeadline {
  final Duration timeout;
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _lastProgress;

  _AudioProgressDeadline(this.timeout);

  void reset() => _lastProgress = null;

  void check({required bool waiting, bool progressed = false, required String operation}) {
    if (!waiting) {
      reset();
      return;
    }
    final now = _clock.elapsed;
    if (progressed || _lastProgress == null) _lastProgress = now;
    if (now - _lastProgress! >= timeout) {
      throw TimeoutException('$operation stopped making progress.', timeout);
    }
  }
}

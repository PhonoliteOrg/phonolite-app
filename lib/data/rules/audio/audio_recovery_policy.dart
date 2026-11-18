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

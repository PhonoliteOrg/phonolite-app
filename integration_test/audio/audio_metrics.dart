import 'dart:math' as math;

/// Native-output progress, sampled by the production engine every 250 ms.
/// These are completed-buffer observations, not acoustic measurements.
class AudioSample {
  const AudioSample({
    required this.atMs,
    required this.positionMs,
    required this.bufferedMs,
    required this.local,
    this.rttMs,
  });

  final int atMs;
  final int positionMs;
  final int bufferedMs;
  final bool local;
  final int? rttMs;

  Map<String, Object?> toJson() => {
    'at_ms': atMs,
    'position_ms': positionMs,
    'buffered_ahead_ms': bufferedMs,
    'local': local,
    'rtt_ms': rttMs,
  };
}

Map<String, Object?> summarizeAudio({
  required List<AudioSample> samples,
  required int elapsedMs,
  required int initialPositionMs,
  required bool expectPlaying,
  required bool expectLocal,
  required int rebufferCount,
  required int errorCount,
  int startupBudgetMs = 3000,
  int stallThresholdMs = 750,
  int maxTelemetryGapMs = 1000,
  double minProgressRatio = .95,
}) {
  final issues = <String>[];
  final matching = samples.where((s) => s.local == expectLocal).toList();
  // A seek can briefly report its old position. Only count output in the
  // requested range; do not mistake a UI seek preview for rendered audio.
  final firstIndex = expectPlaying
      ? matching.indexWhere(
          (s) =>
              s.positionMs > initialPositionMs + 40 &&
              s.positionMs <= initialPositionMs + startupBudgetMs + 1000,
        )
      : -1;
  final first = firstIndex < 0 ? null : matching[firstIndex];
  final steady = first == null ? <AudioSample>[] : matching.sublist(firstIndex);
  var maxGap = matching.isEmpty ? elapsedMs : matching.first.atMs;
  for (var i = 1; i < matching.length; i++) {
    maxGap = math.max(maxGap, matching[i].atMs - matching[i - 1].atMs);
  }
  if (matching.isNotEmpty) {
    maxGap = math.max(maxGap, elapsedMs - matching.last.atMs);
  }
  // Startup latency is reported separately; telemetry is not expected before
  // the engine opens its output. Check cadence after the first observation.
  var steadyMaxGap = 0;
  for (var i = 1; i < matching.length; i++) {
    steadyMaxGap = math.max(
      steadyMaxGap,
      matching[i].atMs - matching[i - 1].atMs,
    );
  }
  if (matching.isNotEmpty) {
    steadyMaxGap = math.max(steadyMaxGap, elapsedMs - matching.last.atMs);
  }
  final stalls = <Map<String, int>>[];
  var regressionCount = 0;
  if (expectPlaying && steady.isNotEmpty) {
    var anchor = steady.first;
    var highWater = anchor.positionMs;
    for (final sample in steady.skip(1)) {
      if (sample.positionMs < highWater - 100) regressionCount++;
      if (sample.positionMs > highWater) {
        final gap = sample.atMs - anchor.atMs;
        if (gap >= stallThresholdMs) {
          stalls.add({'start_ms': anchor.atMs, 'duration_ms': gap});
        }
        highWater = sample.positionMs;
        anchor = sample;
      }
    }
    final trailing = elapsedMs - anchor.atMs;
    if (trailing >= stallThresholdMs) {
      stalls.add({'start_ms': anchor.atMs, 'duration_ms': trailing});
    }
  }
  final steadyWall = steady.length < 2
      ? 0
      : steady.last.atMs - steady.first.atMs;
  final renderedMs = steady.length < 2
      ? 0
      : steady.last.positionMs - steady.first.positionMs;
  final ratio = steadyWall <= 0 ? null : renderedMs / steadyWall;
  // Ignore one callback already in flight when Pause was requested.
  final pausedSamples = matching.where((s) => s.atMs >= 750).toList();
  final pauseDrift = pausedSamples.length < 2
      ? null
      : pausedSamples.map((s) => s.positionMs).reduce(math.max) -
            pausedSamples.map((s) => s.positionMs).reduce(math.min);
  final quality = matching.length < 8 || steadyMaxGap > maxTelemetryGapMs
      ? 'insufficient'
      : 'usable';
  if (quality != 'usable') issues.add('Insufficient or interrupted telemetry');
  if (errorCount > 0) issues.add('$errorCount engine errors');
  if (expectPlaying) {
    if (first == null) {
      issues.add('No native output progress in the requested position range');
    } else if (first.atMs > startupBudgetMs) {
      issues.add('Native output progress exceeded latency budget');
    }
    if (steadyWall < 2000) issues.add('Less than 2 seconds of steady output');
    if (ratio != null && ratio < minProgressRatio) {
      issues.add('Rendered progress fell below the configured ratio');
    }
    if (ratio != null && ratio > 1.10) {
      issues.add('Unexpected position jump or output clock rate');
    }
    if (stalls.isNotEmpty) {
      issues.add('${stalls.length} observed progress stalls');
    }
    if (regressionCount > 0) issues.add('Output position regressed');
    if (rebufferCount > 0) issues.add('$rebufferCount buffering interruptions');
  } else if (pauseDrift == null || pauseDrift > 100) {
    issues.add('Native output did not remain paused');
  }
  return {
    'sample_quality': quality,
    'sample_count': matching.length,
    'elapsed_ms': elapsedMs,
    'first_output_progress_ms': first?.atMs,
    'steady_observed_ms': steadyWall,
    'rendered_progress_ms': renderedMs,
    'rendered_to_wall_ratio': ratio,
    'stall_count': stalls.length,
    'observed_stall_ms': stalls.fold<int>(0, (n, s) => n + s['duration_ms']!),
    'stalls': stalls,
    'rebuffer_count': rebufferCount,
    'engine_error_count': errorCount,
    'position_regression_count': regressionCount,
    'max_telemetry_gap_ms': maxGap,
    'steady_max_telemetry_gap_ms': steadyMaxGap,
    'pause_drift_ms': expectPlaying ? null : pauseDrift,
    'min_buffered_ahead_ms': matching.isEmpty
        ? null
        : matching.map((s) => s.bufferedMs).reduce(math.min),
    // The existing buffer metric includes encoded remote cache. It must not
    // be labelled PCM/output-queue depth or used as an underrun counter.
    'native_underrun_count': null,
    'audible_output_verified': false,
    'issues': issues,
  };
}

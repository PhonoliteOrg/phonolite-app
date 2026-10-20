import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/audio/audio_metrics.dart';

List<AudioSample> samples({
  int count = 25,
  int offset = 0,
  bool paused = false,
  bool local = false,
}) => [
  for (var i = 1; i <= count; i++)
    AudioSample(
      atMs: i * 250,
      positionMs: offset + (paused ? 0 : i * 250),
      bufferedMs: 1500,
      local: local,
    ),
];

Map<String, Object?> summarize(
  List<AudioSample> input, {
  int elapsed = 6250,
  int initial = 0,
  bool playing = true,
  bool local = false,
  int refills = 0,
  int errors = 0,
}) => summarizeAudio(
  samples: input,
  elapsedMs: elapsed,
  initialPositionMs: initial,
  expectPlaying: playing,
  expectLocal: local,
  rebufferCount: refills,
  errorCount: errors,
);

void main() {
  test(
    'continuous native output passes without pretending to measure sound',
    () {
      final result = summarize(samples());
      expect(result['issues'], isEmpty);
      expect(result['rendered_to_wall_ratio'], 1);
      expect(result['first_output_progress_ms'], 250);
      expect(result['native_underrun_count'], isNull);
      expect(result['audible_output_verified'], isFalse);
    },
  );

  test('a recovered stall counts once and reduces rendered progress', () {
    final input = [
      for (var i = 1; i <= 25; i++)
        AudioSample(
          atMs: i * 250,
          positionMs: i < 8
              ? i * 250
              : i <= 12
              ? 1750
              : (i - 5) * 250,
          bufferedMs: 0,
          local: false,
        ),
    ];
    final result = summarize(input, refills: 1);
    expect(result['stall_count'], 1);
    expect(result['observed_stall_ms'], 1500);
    expect(result['rebuffer_count'], 1);
    expect(result['rendered_to_wall_ratio'] as double, lessThan(.95));
    expect(result['issues'], isNotEmpty);
  });

  test('a trailing stall is detected even without a recovery observation', () {
    final input = samples()
        .map(
          (s) => AudioSample(
            atMs: s.atMs,
            positionMs: s.positionMs.clamp(0, 3000),
            bufferedMs: 0,
            local: false,
          ),
        )
        .toList();
    expect(summarize(input)['stall_count'], 1);
  });

  test('missing telemetry is inconclusive, not smooth output', () {
    final result = summarize(
      samples().where((s) => s.atMs < 2000 || s.atMs > 4000).toList(),
    );
    expect(result['sample_quality'], 'insufficient');
    expect(result['issues'], contains('Insufficient or interrupted telemetry'));
    expect(summarize([])['issues'], isNotEmpty);
    expect(
      summarize(samples(count: 4), elapsed: 1000)['sample_quality'],
      'insufficient',
    );
  });

  test(
    'pause excludes the initial callback but requires settled native output',
    () {
      final input = samples(paused: true, offset: 5000);
      expect(
        summarize(input, initial: 5000, playing: false)['issues'],
        isEmpty,
      );
      final drifting = summarize(
        samples(offset: 5000),
        initial: 5000,
        playing: false,
      );
      expect(
        drifting['issues'],
        contains('Native output did not remain paused'),
      );
    },
  );

  test('seek recovery requires native progress near the target', () {
    final input = samples(offset: 30000);
    expect(summarize(input, initial: 30000)['issues'], isEmpty);
    expect(summarize(input, initial: 5000)['issues'], isNotEmpty);
    // Old-position observations after a backward seek cannot satisfy readiness.
    final withOld = [
      const AudioSample(
        atMs: 0,
        positionMs: 90000,
        bufferedMs: 1000,
        local: false,
      ),
      ...input,
    ];
    expect(summarize(withOld, initial: 30000)['first_output_progress_ms'], 250);
  });

  test('resume waits for output beyond the last paused native observation', () {
    final input = [
      const AudioSample(
        atMs: 100,
        positionMs: 5200,
        bufferedMs: 1000,
        local: false,
      ),
      const AudioSample(
        atMs: 350,
        positionMs: 5200,
        bufferedMs: 1000,
        local: false,
      ),
      ...samples(count: 24, offset: 5200).map(
        (s) => AudioSample(
          atMs: s.atMs + 350,
          positionMs: s.positionMs,
          bufferedMs: s.bufferedMs,
          local: false,
        ),
      ),
    ];
    final result = summarize(input, initial: 5200, elapsed: 6350);
    expect(result['first_output_progress_ms'], 600);
    expect(result['issues'], isEmpty);
    final paused = summarize(
      samples(paused: true, offset: 5200),
      initial: 5000,
      playing: false,
    );
    expect(paused['first_output_progress_ms'], isNull);
    expect(paused['rendered_to_wall_ratio'], isNull);
  });

  test('wrong source cannot satisfy a local playback assertion', () {
    expect(summarize(samples(), local: true)['issues'], isNotEmpty);
    expect(summarize(samples(local: true), local: true)['issues'], isEmpty);
  });

  test(
    'startup budget and engine errors independently fail a continuous stream',
    () {
      final late = samples()
          .map(
            (s) => AudioSample(
              atMs: s.atMs + 3500,
              positionMs: s.positionMs,
              bufferedMs: s.bufferedMs,
              local: false,
            ),
          )
          .toList();
      expect(
        summarize(late, elapsed: 9750)['issues'],
        contains('Native output progress exceeded latency budget'),
      );
      expect(
        summarize(samples(), errors: 1)['issues'],
        contains('1 engine errors'),
      );
    },
  );

  test('position regressions and jumps cannot masquerade as smooth output', () {
    final regressing = samples()
        .map(
          (s) => AudioSample(
            atMs: s.atMs,
            positionMs: s.atMs == 3000 ? 1000 : s.positionMs,
            bufferedMs: 1000,
            local: false,
          ),
        )
        .toList();
    expect(summarize(regressing)['position_regression_count'], greaterThan(0));
    final jumping = samples()
        .map(
          (s) => AudioSample(
            atMs: s.atMs,
            positionMs: s.positionMs + (s.atMs > 3000 ? 20000 : 0),
            bufferedMs: 1000,
            local: false,
          ),
        )
        .toList();
    expect(
      summarize(jumping)['issues'],
      contains('Unexpected position jump or output clock rate'),
    );
  });
}

import 'package:phonolite_app/entities/audio_engine.dart';

import 'audio_metrics.dart';
import 'observed_audio_engine.dart';

/// Pass-through observers live exclusively in the integration-test target.
/// The production engine, worker, decoder and output device are unchanged.
class AudioProbe {
  final _clock = Stopwatch();
  final samples = <AudioSample>[];
  final events = <Map<String, Object?>>[];
  final commands = <Map<String, Object?>>[];
  StreamRequest? lastRequest;
  int? lastNativePositionMs;
  bool _collecting = false;
  bool truncated = false;

  AudioEngine createEngine({
    void Function(String message)? onMessage,
    void Function(Duration, Duration, double?, int?, bool)? onStats,
    void Function()? onComplete,
    void Function()? onStarted,
    void Function(bool, bool)? onState,
  }) => ObservedAudioEngine(
    onRequest: (request) => lastRequest = request,
    record: (command) {
      if (_collecting && commands.length < 12000) {
        commands.add({'at_ms': _clock.elapsedMilliseconds, ...command});
      }
    },
    onMessage: (message) {
      if (_collecting) {
        final kind = message.startsWith('Buffer low:')
            ? 'rebuffer'
            : message.startsWith('Buffer recovered:')
            ? 'buffer_recovered'
            : RegExp(
                r'^(Playback failed:|Audio .*failed|Unable to flush audio output)',
              ).hasMatch(message)
            ? 'error'
            : null;
        // Export event categories, not URLs, credentials or local file paths.
        if (kind != null) _event(kind);
      }
      onMessage?.call(message);
    },
    onStats: (position, buffered, bitrate, rtt, local) {
      lastNativePositionMs = position.inMilliseconds;
      if (_collecting) {
        if (samples.length < 12000) {
          samples.add(
            AudioSample(
              atMs: _clock.elapsedMilliseconds,
              positionMs: position.inMilliseconds,
              bufferedMs: buffered.inMilliseconds,
              local: local,
              rttMs: rtt,
            ),
          );
        } else {
          truncated = true;
        }
      }
      onStats?.call(position, buffered, bitrate, rtt, local);
    },
    onStarted: () {
      _event('started');
      onStarted?.call();
    },
    onComplete: () {
      _event('complete');
      onComplete?.call();
    },
    onState: (active, paused) {
      if (_collecting && events.length < 12000) {
        events.add({
          'at_ms': _clock.elapsedMilliseconds,
          'type': 'state',
          'active': active,
          'paused': paused,
        });
      }
      onState?.call(active, paused);
    },
  );

  void _event(String type) {
    if (_collecting && events.length < 12000) {
      events.add({'at_ms': _clock.elapsedMilliseconds, 'type': type});
    }
  }

  void begin() {
    samples.clear();
    events.clear();
    commands.clear();
    truncated = false;
    _clock.reset();
    _clock.start();
    _collecting = true;
  }

  Map<String, Object?> finish({
    required int initialPositionMs,
    bool expectPlaying = true,
    bool expectLocal = false,
    bool afterLastDiscontinuity = false,
  }) {
    _collecting = false;
    _clock.stop();
    final changes = commands.where(
      (c) =>
          c['command'] == 'play' ||
          c['command'] == 'play_local' ||
          c['command'] == 'seek',
    );
    final command = afterLastDiscontinuity && changes.isNotEmpty
        ? changes.last
        : null;
    final startMs = command?['at_ms'] as int? ?? 0;
    final position = command == null
        ? initialPositionMs
        : (command['start_ms'] ?? command['position_ms']) as int;
    final measuredSamples = [
      for (final s in samples)
        if (s.atMs >= startMs)
          AudioSample(
            atMs: s.atMs - startMs,
            positionMs: s.positionMs,
            bufferedMs: s.bufferedMs,
            local: s.local,
            rttMs: s.rttMs,
          ),
    ];
    final measuredEvents = events.where((e) => (e['at_ms'] as int) >= startMs);
    final metrics = summarizeAudio(
      samples: measuredSamples,
      elapsedMs: _clock.elapsedMilliseconds - startMs,
      initialPositionMs: position,
      expectPlaying: expectPlaying,
      expectLocal: expectLocal,
      rebufferCount: measuredEvents
          .where((e) => e['type'] == 'rebuffer')
          .length,
      errorCount: measuredEvents.where((e) => e['type'] == 'error').length,
      startupBudgetMs: const int.fromEnvironment(
        'AUDIO_LATENCY_BUDGET_MS',
        defaultValue: 3000,
      ),
      stallThresholdMs: const int.fromEnvironment(
        'AUDIO_STALL_MS',
        defaultValue: 750,
      ),
    );
    if (truncated) (metrics['issues'] as List).add('Audio samples truncated');
    return {
      'requested_position_ms': position,
      'measurement_start_ms': startMs,
      'expected_playing': expectPlaying,
      'expected_local': expectLocal,
      'metrics': metrics,
      'samples': samples.map((s) => s.toJson()).toList(),
      'events': List.of(events),
      'commands': List.of(commands),
      'samples_truncated': truncated,
    };
  }
}

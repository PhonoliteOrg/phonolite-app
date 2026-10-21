import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  test(
    'stop persists the consumed output tail with its captured session',
    () async {
      final output = _ControlledOutput();
      final fixture = _PlaybackFixture(output: output);
      addTearDown(fixture.close);
      fixture.session.start();
      await waitUntil(() => output.samplesWritten >= 48000);

      // The native output polls its playback head when paused. Only 500ms was
      // actually consumed, regardless of how much PCM the decoder queued.
      output.samplesOnNextPause = 48000;
      await fixture.close().timeout(const Duration(seconds: 2));

      expect(output.disposed, isTrue);
      expect(fixture.segments, hasLength(1));
      final event = fixture.segments.single;
      expect(event['listened_ms'], 500);
      expect(event['end_reason'], 'stopped');
      expect(event['session_id'], 'captured-session');
      expect(event['account_scope'], 'captured-owner');
      expect(event['title'], 'Captured track');
    },
  );

  test('paused playback produces no events without consumed output', () async {
    final output = MemoryPcmOutput();
    final fixture = _PlaybackFixture(output: output, paused: true);
    addTearDown(fixture.close);
    fixture.session.start();
    await waitUntil(() => output.paused && fixture.session.cachedBytes > 100);
    await fixture.session.pause();
    await fixture.close().timeout(const Duration(seconds: 2));

    expect(output.samplesWritten, 0);
    expect(fixture.segments, isEmpty);
  });

  test(
    'rendered playback without collection context produces no events',
    () async {
      final output = MemoryPcmOutput();
      final fixture = _PlaybackFixture(
        output: output,
        collectionEnabled: false,
        complete: true,
      );
      addTearDown(fixture.close);
      fixture.session.start();
      await waitUntil(
        () => fixture.session.messages.any(
          (message) => message['type'] == 'complete',
        ),
      );
      await fixture.close().timeout(const Duration(seconds: 2));

      expect(output.samplesWritten, greaterThan(0));
      expect(fixture.segments, isEmpty);
    },
  );

  test(
    'opt-out discards an uncheckpointed tail and prevents stop collection',
    () async {
      final output = _ControlledOutput();
      final fixture = _PlaybackFixture(output: output);
      addTearDown(fixture.close);
      fixture.session.start();
      await waitUntil(() => output.samplesWritten >= 96000);
      output.completedSamples = 96000;
      // Refreshing the same captured context collects native counters without
      // closing its session or flushing a sub-checkpoint listening interval.
      await fixture.session.configureListening(fixture.context);
      expect(output.completedSamples, 0);
      expect(fixture.segments, isEmpty);

      await fixture.session.configureListening(null);
      output.samplesOnNextPause = 96000;
      await fixture.close().timeout(const Duration(seconds: 2));
      expect(fixture.segments, isEmpty);
    },
  );

  test(
    'account detach flushes recorder and native tail to the old owner',
    () async {
      final output = _ControlledOutput();
      final fixture = _PlaybackFixture(output: output);
      addTearDown(fixture.close);
      fixture.session.start();
      await waitUntil(() => output.samplesWritten >= 96000);
      output.completedSamples = 28800;
      await fixture.session.configureListening(fixture.context);
      expect(fixture.segments, isEmpty);

      output.completedSamples = 67200;
      await fixture.session.configureListening(null, discardPending: false);
      expect(output.completedSamples, 0);
      expect(fixture.segments, hasLength(1));
      final oldSession = fixture.segments.single;
      expect(oldSession['listened_ms'], 1000);
      expect(oldSession['end_reason'], 'interrupted');
      expect(oldSession['account_scope'], 'captured-owner');
      expect(oldSession['session_id'], 'captured-session');

      output.samplesOnNextPause = 96000;
      await fixture.close().timeout(const Duration(seconds: 2));
      expect(fixture.segments, hasLength(1));
    },
  );

  test('EOF collects samples retained by an Android-style idle poll', () async {
    final output = _ControlledOutput()..samplesOnFirstIdlePoll = 24000;
    final fixture = _PlaybackFixture(output: output, complete: true);
    addTearDown(fixture.close);
    fixture.session.start();
    await waitUntil(
      () => fixture.session.messages.any(
        (message) => message['type'] == 'complete',
      ),
    );
    await fixture.close().timeout(const Duration(seconds: 2));

    expect(output.idlePolls, greaterThan(0));
    expect(fixture.segments, isNotEmpty);
    expect(
      fixture.segments.fold<int>(
        0,
        (total, event) => total + (event['listened_ms'] as int),
      ),
      250,
    );
    expect(fixture.segments.last['end_reason'], 'finished');
  });
}

class _PlaybackFixture {
  _PlaybackFixture({
    required MemoryPcmOutput output,
    bool paused = false,
    bool collectionEnabled = true,
    bool complete = false,
  }) {
    transport.onRequest = (start, seekId) => transport.deliverRange(
      startMs: start,
      endMs: start + (complete ? 500 : 5000),
      durationMs: complete ? 500 : 60000,
      seekId: seekId,
      complete: complete,
      endOfTrack: complete,
    );
    session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: paused,
      listeningContext: collectionEnabled ? context : null,
    );
  }

  final transport = MemoryQuic();
  late final AudioPlaybackHarness session;
  final context = <String, dynamic>{
    'session_id': 'captured-session',
    'device_id': 'desktop',
    'track_id': 'track',
    'title': 'Captured track',
    'artist_id': 'artist',
    'artist_name': 'Artist',
    'album_id': 'album',
    'album_title': 'Album',
    'genres': <String>[],
    'artists': <Map<String, dynamic>>[],
    'track_duration_ms': 60000,
    'session_started_at_ms':
        DateTime.now().toUtc().millisecondsSinceEpoch - 1000,
    'rule_version': 1,
    'account_scope': 'captured-owner',
    'history_generation': 1,
  };
  Future<void>? _closing;

  List<Map<String, dynamic>> get segments => [
    for (final message in session.messages)
      if (message['type'] == 'listening_segment')
        Map<String, dynamic>.from(message['event'] as Map),
  ];

  Future<void> close() => _closing ??= session.close();
}

/// Model native consumed counters separately from queued PCM. Android idle and
/// pause probes retain completed frames until collectDoneSamples consumes them.
class _ControlledOutput extends MemoryPcmOutput {
  int completedSamples = 0;
  int samplesOnNextPause = 0;
  int samplesOnFirstIdlePoll = 0;
  int idlePolls = 0;

  @override
  void pause() {
    super.pause();
    completedSamples += samplesOnNextPause;
    samplesOnNextPause = 0;
  }

  @override
  Future<int> collectDoneSamples() async {
    final done = completedSamples;
    completedSamples = 0;
    return done;
  }

  @override
  Future<bool> isIdle() async {
    idlePolls++;
    completedSamples += samplesOnFirstIdlePoll;
    samplesOnFirstIdlePoll = 0;
    return true;
  }
}

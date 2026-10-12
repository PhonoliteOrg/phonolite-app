import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/listening_recorder.dart';

void main() {
  test(
    'absent collection context does not emit even at playback boundaries',
    () {
      final harness = _RecorderHarness(context: null);
      harness.addMilliseconds(60000);
      harness.recorder.flush(endReason: 'finished');
      expect(harness.events, isEmpty);
      expect(harness.recorder.enabled, isFalse);
    },
  );

  test(
    'interleaved stereo samples retain fractional milliseconds accurately',
    () {
      final harness = _RecorderHarness();
      for (var chunk = 0; chunk < 441; chunk++) {
        harness.advance(3);
        harness.recorder.addSamples(200, sampleRate: 44100, channels: 2);
      }
      harness.recorder.flush(endReason: 'finished');
      expect(harness.events, hasLength(1));
      expect(harness.events.single['listened_ms'], 1000);
      expect(
        harness.events.single['ended_at_ms'],
        greaterThanOrEqualTo(harness.events.single['started_at_ms'] as int),
      );
    },
  );

  test(
    'sample-rate changes do not reinterpret a previous fractional remainder',
    () {
      final harness = _RecorderHarness();
      harness.advance(1);
      harness.recorder.addSamples(47, sampleRate: 48000, channels: 1);
      harness.advance(1000);
      harness.recorder.addSamples(44100, sampleRate: 44100, channels: 1);
      harness.recorder.flush();
      expect(harness.events.single['listened_ms'], 1000);
    },
  );

  test(
    'checkpoints are based on consumed duration and final marker is unique',
    () {
      final harness = _RecorderHarness();
      harness.addMilliseconds(14999);
      expect(harness.events, isEmpty);
      harness.addMilliseconds(1);
      expect(harness.events, hasLength(1));
      expect(harness.events.single['listened_ms'], 15000);
      expect(harness.events.single.containsKey('end_reason'), isFalse);
      harness.recorder.flush(endReason: 'finished');
      harness.recorder.flush(endReason: 'finished');
      harness.addMilliseconds(1000);
      expect(harness.events, hasLength(2));
      expect(harness.events.last['listened_ms'], 0);
      expect(harness.events.last['end_reason'], 'finished');
      expect(
        harness.events.map((event) => event['event_id']).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'pause or seek flush retains session and excludes time without audio',
    () {
      final harness = _RecorderHarness();
      harness.addMilliseconds(1000);
      harness.recorder.flush();
      harness.advance(3600000);
      harness.addMilliseconds(250);
      harness.recorder.flush(endReason: 'stopped');
      expect(harness.events, hasLength(2));
      expect(harness.events.map((event) => event['session_id']).toSet(), {
        'session',
      });
      expect(
        harness.events.fold<int>(
          0,
          (total, event) => total + (event['listened_ms'] as int),
        ),
        1250,
      );
      expect(
        harness.events.last['started_at_ms'],
        greaterThan(harness.events.first['ended_at_ms'] as int),
      );
    },
  );

  test('opt-out discards tail and re-enabling creates a clean session', () {
    final harness = _RecorderHarness();
    harness.addMilliseconds(1000);
    harness.recorder.setContext(null);
    harness.addMilliseconds(30000);
    harness.recorder.flush(endReason: 'stopped');
    expect(harness.events, isEmpty);
    expect(harness.recorder.enabled, isFalse);

    harness.recorder.setContext(harness.context('enabled-again'));
    harness.addMilliseconds(500);
    harness.recorder.flush(endReason: 'stopped');
    expect(harness.events, hasLength(1));
    expect(harness.events.single['session_id'], 'enabled-again');
    expect(harness.events.single['listened_ms'], 500);
  });

  test(
    'changing owner flushes previous captured metadata before new context',
    () {
      final harness = _RecorderHarness();
      harness.addMilliseconds(1000);
      final next = harness.context('new-session')
        ..['track_id'] = 'new-track'
        ..['title'] = 'New track'
        ..['account_scope'] = 'new-owner';
      harness.recorder.setContext(next);
      expect(harness.events.single['account_scope'], 'old-owner');
      expect(harness.events.single['title'], 'Old track');
      expect(harness.events.single['end_reason'], 'interrupted');
      harness.addMilliseconds(500);
      harness.recorder.flush(endReason: 'finished');
      expect(harness.events.last['account_scope'], 'new-owner');
      expect(harness.events.last['title'], 'New track');
      expect(harness.events.last['listened_ms'], 500);
    },
  );

  test('unheard sessions never generate an end marker', () {
    final harness = _RecorderHarness();
    harness.advance(3600000);
    harness.recorder.flush(endReason: 'interrupted');
    harness.recorder.addSamples(0, sampleRate: 48000, channels: 2);
    harness.recorder.addSamples(-1, sampleRate: 48000, channels: 2);
    harness.recorder.addSamples(1000, sampleRate: 0, channels: 2);
    harness.recorder.flush(endReason: 'finished');
    expect(harness.events, isEmpty);
  });

  test('late output backlog cannot precede the captured session start', () {
    final harness = _RecorderHarness();
    // Activating collection on an already running output may return a native
    // backlog larger than the elapsed time since this context was created.
    harness.advance(10);
    harness.recorder.addSamples(24000, sampleRate: 48000, channels: 2);
    harness.recorder.flush(endReason: 'stopped');
    expect(
      harness.events.single['started_at_ms'],
      greaterThanOrEqualTo(
        harness.events.single['session_started_at_ms'] as int,
      ),
    );
  });

  test(
    'clock rollback keeps zero-duration final marker inside its session',
    () {
      final harness = _RecorderHarness();
      harness.addMilliseconds(15000);
      expect(harness.events, hasLength(1));
      harness.advance(-30000);
      harness.recorder.flush(endReason: 'finished');
      expect(harness.events, hasLength(2));
      final marker = harness.events.last;
      expect(marker['listened_ms'], 0);
      expect(marker['end_reason'], 'finished');
      expect(
        marker['started_at_ms'],
        greaterThanOrEqualTo(marker['session_started_at_ms'] as int),
      );
      expect(
        marker['ended_at_ms'],
        greaterThanOrEqualTo(marker['started_at_ms'] as int),
      );
      expect(harness.events.first['listened_ms'], 15000);
    },
  );
}

class _RecorderHarness {
  _RecorderHarness({Object? context = true}) {
    recorder = ListeningRecorder(
      playbackId: 7,
      emit: events.add,
      context: context == null ? null : this.context('session'),
      clock: () => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    );
  }

  int now = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
  final events = <Map<String, dynamic>>[];
  late final ListeningRecorder recorder;

  Map<String, dynamic> context(String session) => {
    'session_id': session,
    'session_started_at_ms': now,
    'device_id': 'desktop',
    'track_id': 'track',
    'title': 'Old track',
    'account_scope': 'old-owner',
    'history_generation': 1,
  };

  void advance(int milliseconds) => now += milliseconds;

  void addMilliseconds(int milliseconds) {
    advance(milliseconds);
    recorder.addSamples(milliseconds * 96, sampleRate: 48000, channels: 2);
  }
}

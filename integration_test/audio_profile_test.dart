import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';

import 'audio/audio_probe.dart';
import 'audio/audio_test_host.dart';
import 'support/journey.dart';
import 'support/report_channel.dart';
import 'support/ui_harness.dart';

void main() {
  final reports = UiReportChannel()..register();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Real audio streaming and native output continuity', (tester) async {
    expect(kProfileMode, isTrue, reason: 'Use flutter drive --profile');
    const seconds = int.fromEnvironment('AUDIO_SECONDS', defaultValue: 30);
    const mode = String.fromEnvironment('AUDIO_MODE', defaultValue: 'all');
    expect(seconds, inInclusiveRange(8, 300));
    expect(mode, isIn(['all', 'stream', 'local']));
    expect(const int.fromEnvironment('AUDIO_LATENCY_BUDGET_MS', defaultValue: 3000), greaterThan(0));
    expect(const int.fromEnvironment('AUDIO_STALL_MS', defaultValue: 750), greaterThanOrEqualTo(500));
    final probe = AudioProbe();
    final output = binding.reportData ??= <String, dynamic>{};
    final ids = [
      if (mode != 'local') ...[
        'audio.stream_start_and_ui_load',
        'audio.pause',
        'audio.resume',
        'audio.seek_forward',
        'audio.seek_backward',
        'audio.next_track',
      ],
      if (mode != 'stream') 'audio.local_playback',
    ];
    output.addAll({
      'schema_version': 1,
      'suite': 'audio',
      'build_mode': 'profile',
      'platform': defaultTargetPlatform.name,
      'selected_journeys': ids,
      'capture_timeline': UiHarness.captureTimeline,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'audio_seconds': seconds,
      'audio_mode': mode,
      'latency_budget_ms': const int.fromEnvironment('AUDIO_LATENCY_BUDGET_MS', defaultValue: 3000),
      'stall_threshold_ms': const int.fromEnvironment('AUDIO_STALL_MS', defaultValue: 750),
      'minimum_rendered_to_wall_ratio': .95,
      'native_underrun_counter_available': false,
      'acoustic_recording': false,
      'action_layer': 'production controller commands with real HomePage UI load',
    });
    await reports.publish({
      'type': 'run_metadata',
      'metadata': {...output},
    });
    final controller = await startAudioTestHost(probe);
    final ui = UiHarness(tester, binding);
    final failures = <String>[];
    var exercised = 0;
    try {
      await ui.ready();
      output['signed_in'] = controller.authState.isAuthorized;
      output['available_local_tracks'] = controller.availableOfflineDownloads.length;
      String? streamPrerequisite;
      ({String albumId, Track track})? fixture;
      if (mode != 'local') {
        if (!controller.authState.isAuthorized) {
          streamPrerequisite = 'A restored server session is required';
        } else {
          // Read-only discovery; no downloads, likes or playlists are changed.
          await controller.loadArtists();
          const albumOverride = String.fromEnvironment('AUDIO_ALBUM_ID');
          final albums = <Album>[];
          if (albumOverride.isNotEmpty) {
            albums.add(await controller.connection.fetchAlbumById(albumOverride));
          } else {
            for (final artist in controller.artists.take(4)) {
              albums.addAll(await controller.connection.fetchAlbums(artist.id));
              if (albums.length >= 8) break;
            }
          }
          for (final album in albums.take(12)) {
            final tracks = await controller.connection.fetchTracks(album.id);
            for (var i = 0; i + 1 < tracks.length; i++) {
              if (tracks[i].durationMs >= (seconds + 60) * 1000 && tracks[i + 1].durationMs >= 15000) {
                fixture = (albumId: album.id, track: tracks[i]);
                break;
              }
            }
            if (fixture != null) break;
          }
          if (fixture == null) {
            streamPrerequisite = 'Need an album with a sufficiently long track and a next track';
          }
        }
      }
      if (fixture != null) {
        output['fixture_album_id'] = fixture.albumId;
        output['fixture_track_id'] = fixture.track.id;
        output['fixture_duration_ms'] = fixture.track.durationMs;
      }
      await reports.publish({
        'type': 'run_metadata',
        'metadata': {...output},
      });

      Future<void> capture(
        String id,
        String description, {
        required Future<void> Function() action,
        required int initialPositionMs,
        int holdSeconds = 8,
        bool playing = true,
        bool local = false,
        bool uiLoad = false,
        String? prerequisite,
      }) async {
        Map<String, Object?>? audio;
        await reports.publish({'type': 'journey_start', 'id': id});
        try {
          await ui.measure(
            UiJourney(
              id: id,
              feature: 'audio',
              description: description,
              // Audio commands are not evidence that a UI gesture was covered.
              interactions: const [],
              run: (_) async {
                if (prerequisite != null) {
                  throw MissingPrerequisite(prerequisite);
                }
                probe.begin();
                try {
                  await action();
                  final clock = Stopwatch()..start();
                  const tabs = ['Library', 'Playlists', 'Liked', 'Settings'];
                  var index = 0;
                  while (clock.elapsed < Duration(seconds: holdSeconds)) {
                    if (uiLoad) await ui.tab(tabs[index++ % tabs.length]);
                    await ui.animate(500);
                  }
                } finally {
                  audio = probe.finish(
                    initialPositionMs: initialPositionMs,
                    expectPlaying: playing,
                    expectLocal: local,
                  );
                  audio!['track_id'] = controller.playbackState.track?.id;
                  audio!['stream_mode'] = controller.playbackState.streamMode.name;
                }
                expect((audio!['metrics'] as Map)['issues'], isEmpty, reason: '$id: ${audio!['metrics']}');
                if (playing) {
                  expect(controller.playbackState.isPlaying, isTrue);
                  expect(controller.playbackState.isLocalPlayback, local);
                } else {
                  expect(controller.playbackState.isPlaying, isFalse);
                }
                exercised++;
              },
            ),
          );
        } catch (error, stack) {
          failures.add(id);
          debugPrint('[audio] $id failed: $error');
          debugPrintStack(stackTrace: stack);
        } finally {
          final result = (output['journeys'] as List).last as Map;
          if (audio != null) result['audio'] = audio;
          await reports.publish({'type': 'journey_result', 'journey': result});
          result.remove('frames');
          result.remove('audio');
        }
      }

      if (mode != 'local') {
        await capture(
          'audio.stream_start_and_ui_load',
          'Start a real server stream; exercise navigation during sustained native output',
          initialPositionMs: 0,
          holdSeconds: seconds,
          uiLoad: true,
          prerequisite: streamPrerequisite,
          action: () async {
            await controller.queueAlbum(fixture!.albumId, startTrackId: fixture.track.id);
            expect(controller.playbackState.track?.id, fixture.track.id);
          },
        );
        final dependentPrerequisite =
            streamPrerequisite ?? (controller.playbackState.track == null ? 'No active streamed track' : null);
        await capture(
          'audio.pause',
          'Native progress remains still after Pause',
          initialPositionMs: controller.playbackState.position.inMilliseconds,
          playing: false,
          holdSeconds: 3,
          prerequisite: dependentPrerequisite,
          action: () => controller.pause(true),
        );
        await capture(
          'audio.resume',
          'Resume the same stream and verify native output recovery',
          // The UI deliberately holds its position while paused. A final
          // native callback may be ahead of it; use actual output as baseline.
          initialPositionMs: probe.samples.isEmpty
              ? controller.playbackState.position.inMilliseconds
              : probe.samples.last.positionMs,
          prerequisite: dependentPrerequisite,
          action: () => controller.pause(false),
        );
        final forwardMs = fixture == null
            ? 30000
            : (controller.playbackState.position.inMilliseconds + 15000).clamp(15000, fixture.track.durationMs - 15000);
        await capture(
          'audio.seek_forward',
          'Seek forward and verify native output in the requested range',
          initialPositionMs: forwardMs,
          prerequisite: dependentPrerequisite,
          action: () => controller.seekTo(Duration(milliseconds: forwardMs)),
        );
        await capture(
          'audio.seek_backward',
          'Seek backward and verify output continuity after recovery',
          initialPositionMs: 5000,
          prerequisite: dependentPrerequisite,
          action: () => controller.seekTo(const Duration(seconds: 5)),
        );
        final previousId = controller.playbackState.track?.id;
        await capture(
          'audio.next_track',
          'Advance the queue and verify the next track produces output',
          initialPositionMs: 0,
          prerequisite: dependentPrerequisite,
          action: () async {
            await controller.nextTrack();
            expect(controller.playbackState.track?.id, isNot(previousId));
          },
        );
      }
      if (mode != 'stream') {
        final downloads = controller.availableOfflineDownloads.where((d) => d.track.durationMs >= 20000).toList();
        await capture(
          'audio.local_playback',
          'Play an existing downloaded file through the native decoder and output',
          initialPositionMs: 0,
          local: true,
          holdSeconds: 12,
          prerequisite: downloads.isEmpty ? 'No existing downloaded track of at least 20 seconds' : null,
          action: () => controller.playOfflineTrack(downloads.first.track.id),
        );
      }
      output['failed_journeys'] = failures;
      expect(exercised, greaterThan(0), reason: 'No audio scenario was verified');
      expect(failures, isEmpty, reason: 'See the per-scenario audio report');
    } finally {
      // Playback is explicitly opt-in. Always stop it, including on failure.
      await controller.stop();
      output['finished_at'] = DateTime.now().toUtc().toIso8601String();
      await reports.publish({
        'type': 'run_metadata',
        'metadata': Map<String, dynamic>.from(output)..remove('journeys'),
      });
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

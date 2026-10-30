import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/features/playback/widgets/device_picker_modal.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';

import '../support/journey.dart';
import '../support/report_channel.dart';
import '../support/ui_harness.dart';
import 'audio_probe.dart';
import 'quality_wire_probe.dart';

const playerControlIds = [
  'audio.mini_pause',
  'audio.mini_resume',
  'audio.mini_next',
  'audio.expand',
  'audio.expanded_previous',
  'audio.expanded_pause',
  'audio.expanded_resume',
  'audio.slider_forward',
  'audio.slider_backward',
  'audio.quality_low',
  'audio.quality_medium',
  'audio.quality_high',
  'audio.quality_original',
  'audio.quality_while_paused',
  'audio.quality_resume',
  'audio.repeat_button',
  'audio.shuffle_button',
  'audio.volume_slider',
  'audio.like_button',
  'audio.playlist_button',
  'audio.output_button',
  'audio.artwork_details',
  'audio.dismiss',
  'audio.stop_button',
  'audio.wire_high',
  'audio.wire_medium',
  'audio.wire_low',
  'audio.wire_ordering',
];

class PlayerControlsSuite {
  PlayerControlsSuite(this.ui, this.probe, this.reports, this.output);
  final UiHarness ui;
  final AudioProbe probe;
  final UiReportChannel reports;
  final Map<String, dynamic> output;
  final failures = <String>[];
  Map<String, Object?> checks = {};
  Map<String, Object?> extra = {};
  String? _temporaryPlaylistId;
  Track? _likedTrack;
  bool? _originalLike;
  late PlaybackState _original;
  late Track track;
  late String albumId;
  AppController get controller => ui.controller;
  Finder get mini => find.byType(NowPlayingMiniBar);
  Finder get sheet => find.byType(NowPlayingExpandedSheet);
  Finder within(Finder root, Finder control) => find.descendant(of: root, matching: control);
  Finder icon(IconData value, {bool compact = false}) => within(compact ? mini : sheet, find.byIcon(value));

  void checked(String name, [Object? value = true]) => checks[name] = value;

  Future<void> waitRemote(Future<bool> Function() condition, String description) async {
    final clock = Stopwatch()..start();
    while (!await condition()) {
      if (clock.elapsed > const Duration(seconds: 12)) {
        fail('Timed out: $description');
      }
      await ui.animate(250);
    }
  }

  Future<void> capture(
    String id,
    String description,
    Future<void> Function() action, {
    bool audio = false,
    bool playing = true,
    int? baseline,
    int Function()? requestedPosition,
  }) async {
    checks = {};
    extra = {};
    Map<String, Object?>? observation;
    await reports.publish({'type': 'journey_start', 'id': id});
    try {
      await ui.measure(
        UiJourney(
          id: id,
          feature: 'audio',
          description: description,
          interactions: const [],
          run: (_) async {
            final before = baseline ?? probe.lastNativePositionMs ?? controller.playbackState.position.inMilliseconds;
            probe.begin();
            try {
              await action();
              if (audio) await ui.animate(playing ? 4000 : 3000);
            } finally {
              final collected = probe.finish(
                initialPositionMs: requestedPosition?.call() ?? before,
                expectPlaying: playing,
                afterLastDiscontinuity: true,
              );
              if (audio) observation = collected;
              extra['commands'] = collected['commands'];
            }
            if (audio) {
              expect((observation!['metrics'] as Map)['issues'], isEmpty, reason: '$id: ${observation!['metrics']}');
              expect(controller.playbackState.isPlaying, playing);
            }
            expect(checks, isNotEmpty, reason: 'A control needs an observable effect');
          },
        ),
      );
    } catch (error, stack) {
      failures.add(id);
      debugPrint('[controls] $id failed: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      final result = (output['journeys'] as List).last as Map<String, Object?>;
      result.addAll({'checks': checks, ...extra, if (observation != null) 'audio': observation});
      await reports.publish({'type': 'journey_result', 'journey': result});
      result.remove('frames');
      result.remove('audio');
      if (result['status'] == 'failed') {
        // Recovery only: an open dialog must not invalidate later controls.
        await ui.resetNavigation();
        if (!id.startsWith('audio.mini_') && !id.startsWith('audio.wire_')) {
          await open();
        }
      }
    }
  }

  Future<void> seed() async {
    _original = controller.playbackState;
    expect(controller.authState.isAuthorized, isTrue, reason: 'A signed-in real server is required');
    await controller.loadArtists();
    final albums = <Album>[];
    const override = String.fromEnvironment('AUDIO_ALBUM_ID');
    if (override.isNotEmpty) {
      albums.add(await controller.connection.fetchAlbumById(override));
    } else {
      for (final artist in controller.artists.take(4)) {
        albums.addAll(await controller.connection.fetchAlbums(artist.id));
        if (albums.length >= 8) break;
      }
    }
    Track? selected;
    for (final album in albums.take(12)) {
      final tracks = await controller.connection.fetchTracks(album.id);
      for (var index = 0; index + 1 < tracks.length; index++) {
        if (tracks[index].durationMs >= 180000 && tracks[index + 1].durationMs >= 30000) {
          selected = tracks[index];
          albumId = album.id;
          break;
        }
      }
      if (selected != null) break;
    }
    expect(selected, isNotNull, reason: 'Need a three-minute album track and another queue track');
    track = selected!;
    output.addAll({
      'fixture_album_id': albumId,
      'fixture_track_id': track.id,
      'fixture_duration_ms': track.durationMs,
      'quality_targets_bps': qualityTargets,
    });
    // Setup only. All controls under test below are operated with real taps.
    controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await controller.queueAlbum(albumId, startTrackId: track.id);
    await ui.waitUntil(
      () => !controller.playbackState.isLoading && (probe.lastNativePositionMs ?? 0) > 40,
      description: 'initial native audio output',
    );
  }

  Future<void> open() async {
    await ui.tap(within(mini, find.byType(InkWell)).first);
    await ui.waitFor(sheet);
  }

  Future<void> dismiss() async {
    final rect = ui.tester.getRect(sheet);
    await ui.tester.flingFrom(Offset(rect.center.dx, rect.top + 18), Offset(0, rect.height * .8), 1800);
    await ui.animate(800);
    expect(sheet, findsNothing);
  }

  Future<void> chooseQuality(StreamMode mode) async {
    const labels = {
      StreamMode.high: 'HQ',
      StreamMode.medium: 'MQ',
      StreamMode.low: 'LQ',
      StreamMode.auto: 'AUTO',
      StreamMode.original: 'OG',
    };
    const modalLabels = {
      StreamMode.original: 'Original (source-preserving · QUIC)',
      StreamMode.high: 'High quality (160 kbps)',
      StreamMode.medium: 'Medium quality (96 kbps)',
      StreamMode.low: 'Low quality (48 kbps)',
    };
    await ui.tap(within(sheet, find.text(labels[controller.playbackState.streamMode]!)));
    await ui.waitFor(find.text('Stream Quality'));
    expect(find.text('Original (source-preserving · QUIC)'), findsOneWidget);
    expect(find.text('High quality (160 kbps)'), findsOneWidget);
    expect(find.text('Medium quality (96 kbps)'), findsOneWidget);
    expect(find.text('Low quality (48 kbps)'), findsOneWidget);
    // The custom dialog builds a Material dialog, not necessarily AlertDialog.
    final option = find.text(modalLabels[mode]!).hitTestable();
    await ui.tap(option.last);
    expect(find.text('Stream Quality'), findsNothing);
    expect(controller.playbackState.streamMode, mode);
    checked('quality_selected', mode.name);
  }

  Future<void> run() async {
    await capture(
      'audio.mini_pause',
      'Compact playbar Pause stops native progress',
      () async {
        await ui.tap(icon(Icons.pause, compact: true));
        expect(probe.commands.any((c) => c['command'] == 'pause'), isTrue);
        checked('pause_reached_engine');
      },
      audio: true,
      playing: false,
    );
    await capture('audio.mini_resume', 'Compact playbar Play resumes native output', () async {
      await ui.tap(icon(Icons.play_arrow, compact: true));
      checked('resume_reached_engine', probe.commands.any((c) => c['command'] == 'resume'));
      expect(checks['resume_reached_engine'], isTrue);
    }, audio: true);
    await capture(
      'audio.mini_next',
      'Compact Next advances to another playing track',
      () async {
        final previous = controller.playbackState.track!.id;
        await ui.tap(icon(PhonoliteIcons.skipForward, compact: true));
        await ui.waitUntil(
          () => controller.playbackState.track?.id != previous && !controller.playbackState.isLoading,
          description: 'next track',
        );
        checked('queue_advanced');
      },
      audio: true,
      baseline: 0,
    );
    await capture('audio.expand', 'Compact player body opens the expanded tray', () async {
      await open();
      checked('expanded_tray_visible');
    });
    await capture(
      'audio.expanded_previous',
      'Previous returns to the preceding album track',
      () async {
        await ui.tap(icon(PhonoliteIcons.skipBack));
        await ui.waitUntil(
          () => controller.playbackState.track?.id == track.id && !controller.playbackState.isLoading,
          description: 'previous album track',
        );
        checked('previous_track_restored');
      },
      audio: true,
      baseline: 0,
    );
    await capture(
      'audio.expanded_pause',
      'Expanded Pause stops native progress',
      () async {
        await ui.tap(icon(Icons.pause));
        expect(controller.playbackState.isPlaying, isFalse);
        checked('expanded_pause');
      },
      audio: true,
      playing: false,
    );
    await capture('audio.expanded_resume', 'Expanded Play resumes the same track', () async {
      await ui.tap(icon(Icons.play_arrow));
      expect(controller.playbackState.track!.id, track.id);
      checked('expanded_resume');
    }, audio: true);
    for (final forward in [true, false]) {
      var requested = 0;
      await capture(
        'audio.slider_${forward ? 'forward' : 'backward'}',
        'Visible progress slider commits a ${forward ? 'forward' : 'backward'} seek',
        () async {
          final slider = within(sheet, find.byWidgetPredicate((w) => w is Slider && w.max > 1));
          final before = controller.playbackState.position.inMilliseconds;
          final rect = ui.tester.getRect(slider);
          final position = Offset(rect.left + 24 + (rect.width - 48) * (forward ? .35 : .08), rect.center.dy);
          await ui.tester.tapAt(position);
          await ui.animate(700);
          final seek = probe.commands.where((c) => c['command'] == 'seek');
          expect(seek, isNotEmpty, reason: 'Slider must commit an engine seek');
          requested = seek.last['position_ms'] as int;
          expect(requested, forward ? greaterThan(before) : lessThan(before));
          checked('seek_committed_ms', requested);
        },
        audio: true,
        requestedPosition: () => requested,
      );
    }
    for (final quality in [StreamMode.low, StreamMode.medium, StreamMode.high, StreamMode.original]) {
      final profile = quality.name;
      final source = quality == StreamMode.original;
      await capture(
        'audio.quality_$profile',
        'Select $profile quality while playing and verify engine request/output',
        () async {
          await chooseQuality(quality);
          await ui.waitUntil(
            () => probe.commands.any((c) => c['command'] == 'play' && c['quality'] == (source ? 'source' : profile)),
            description: '$profile engine request',
          );
          final request = probe.commands.lastWhere((c) => c['command'] == 'play');
          expect(request['mode'], source ? 'original' : 'fixed');
          expect(request['frame_ms'], 20);
          expect(controller.playbackState.track!.id, track.id);
          checked('stream_quality_request', request);
        },
        audio: true,
      );
    }
    await capture(
      'audio.quality_while_paused',
      'Choose LQ while paused without starting audible playback',
      () async {
        await ui.tap(icon(Icons.pause));
        await chooseQuality(StreamMode.low);
        await ui.waitUntil(
          () => !controller.playbackState.isLoading,
          description: 'paused quality selection readiness',
        );
        expect(controller.playbackState.isPlaying, isFalse);
        checked('quality_change_preserved_pause');
      },
      audio: true,
      playing: false,
    );
    await capture('audio.quality_resume', 'Resume uses the quality selected while paused', () async {
      await ui.tap(icon(Icons.play_arrow));
      await ui.waitUntil(
        () => probe.lastRequest?.settings.quality == 'low',
        description: 'LQ applied to resumed native stream',
        timeout: const Duration(seconds: 5),
      );
      checked('resumed_quality', probe.lastRequest!.settings.quality);
    }, audio: true);
    await capture('audio.repeat_button', 'Repeat toggles and persists on the server, then restores', () async {
      final before = controller.playbackState.repeatMode;
      final expected = before == PlaybackRepeatMode.off ? PlaybackRepeatMode.one : PlaybackRepeatMode.off;
      await ui.tap(icon(PhonoliteIcons.repeat));
      expect(controller.playbackState.repeatMode, expected);
      await waitRemote(
        () async => (await controller.connection.fetchPlaybackSettings()).repeatMode == expected.name,
        'server repeat setting',
      );
      await ui.tap(icon(PhonoliteIcons.repeat));
      await waitRemote(
        () async => (await controller.connection.fetchPlaybackSettings()).repeatMode == before.name,
        'restored server repeat setting',
      );
      checked('repeat_ui_and_server_restored');
    });
    await capture('audio.shuffle_button', 'Shuffle selects Current Album and returns to Off', () async {
      await ui.tap(icon(PhonoliteIcons.shuffle));
      await ui.waitFor(find.text('Shuffle'));
      await ui.text('Current Album');
      expect(controller.playbackState.shuffleMode, ShuffleMode.album);
      await ui.tap(icon(PhonoliteIcons.shuffle));
      await ui.text('Off');
      expect(controller.playbackState.shuffleMode, ShuffleMode.off);
      checked('shuffle_album_and_off');
    });
    await capture(
      'audio.volume_slider',
      'Volume slider reaches the engine and returns to the original value',
      () async {
        final initial = controller.playbackState.volume;
        final slider = within(sheet, find.byWidgetPredicate((w) => w is Slider && w.max == 1));
        if (slider.evaluate().isEmpty) {
          throw const MissingPrerequisite(
            'The native mobile tray intentionally has no app volume slider; use system volume',
          );
        }
        final rect = ui.tester.getRect(slider);
        await ui.tester.tapAt(Offset(rect.left + 24 + (rect.width - 48) * .4, rect.center.dy));
        await ui.animate(500);
        final value = controller.playbackState.volume;
        expect(value, inInclusiveRange(.25, .55));
        expect(probe.commands.any((c) => c['command'] == 'volume' && c['value'] == value), isTrue);
        // Drag to the saved value, then use exact cleanup to avoid rounding drift.
        await ui.tester.tapAt(Offset(rect.left + 24 + (rect.width - 48) * initial, rect.center.dy));
        await ui.animate(400);
        controller.setVolume(initial);
        checked('volume_reached_engine_and_restored', value);
      },
    );
    await capture('audio.like_button', 'Like toggles on the server and restores its original state', () async {
      _likedTrack = controller.playbackState.track!;
      _originalLike = (await controller.connection.fetchLikedTracks()).any((t) => t.id == _likedTrack!.id);
      expect(controller.playbackState.track!.liked, _originalLike);
      await ui.tap(within(sheet, find.byType(LikeIconButton)));
      await waitRemote(
        () async =>
            (await controller.connection.fetchLikedTracks()).any((t) => t.id == _likedTrack!.id) != _originalLike,
        'changed server like state',
      );
      await ui.tap(within(sheet, find.byType(LikeIconButton)));
      await waitRemote(
        () async =>
            (await controller.connection.fetchLikedTracks()).any((t) => t.id == _likedTrack!.id) == _originalLike,
        'restored server like state',
      );
      checked('like_server_round_trip_restored');
    });
    await capture(
      'audio.playlist_button',
      'Add-to-playlist opens and adds to an isolated temporary playlist',
      () async {
        final name = 'Playback test ${DateTime.now().microsecondsSinceEpoch}';
        final playlist = await controller.connection.createPlaylist(name);
        _temporaryPlaylistId = playlist.id;
        await controller.loadPlaylists();
        await ui.tap(within(sheet, find.byType(PlaylistAddIcon)));
        await ui.waitFor(find.byType(AddToPlaylistModal));
        final modal = ui.tester.widget<AddToPlaylistModal>(find.byType(AddToPlaylistModal));
        expect(modal.canUsePlaylists, isTrue);
        final field = within(find.byType(AddToPlaylistModal), find.byType(TextField));
        await ui.tester.enterText(field, name);
        await ui.animate(350);
        // find.text also matches the identical query in EditableText.
        await ui.tap(find.byWidgetPredicate((w) => w is Text && w.data == name));
        await waitRemote(
          () async => (await controller.connection.fetchPlaylistTracks(playlist.id)).any((t) => t.id == modal.trackId),
          'track added by playbar action',
        );
        await ui.closeDialog();
        checked('playlist_add_verified');
        await controller.deletePlaylist(playlist.id);
        expect((await controller.connection.fetchPlaylists()).any((p) => p.id == playlist.id), isFalse);
        _temporaryPlaylistId = null;
        checked('temporary_playlist_deleted');
      },
    );
    await capture(
      'audio.output_button',
      'Output picker opens, refreshes and accepts the available current route',
      () async {
        await ui.tap(icon(PhonoliteIcons.speaker));
        await ui.waitFor(find.byType(DevicePickerModal));
        await ui.waitUntil(() => controller.outputDevices.isNotEmpty, description: 'output device list');
        await ui.text('REFRESH');
        expect(probe.commands.where((c) => c['command'] == 'list_devices').length, greaterThanOrEqualTo(2));
        final selected = controller.outputDevices.firstWhere((d) => d.id == controller.outputDeviceId);
        await ui.text(selected.name);
        expect(find.byType(DevicePickerModal), findsNothing);
        expect(controller.outputDeviceId, selected.id);
        checked('output_open_refresh_select_current');
        checked('available_route_count', controller.outputDevices.length);
        checked('alternate_hardware_route_tested', false);
      },
    );
    await capture('audio.artwork_details', 'Expanded artwork/details opens the playing album', () async {
      // The large artwork and title area share the album navigation action.
      final gestures = within(sheet, find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null));
      await ui.tap(gestures.first);
      await ui.waitFor(ui.command('Back to artist'));
      expect(sheet, findsNothing);
      checked('playing_album_opened');
      await ui.resetNavigation();
      await open();
    });
    await capture('audio.dismiss', 'Swipe dismissal returns to compact playbar without stopping audio', () async {
      await dismiss();
      expect(controller.playbackState.isPlaying, isTrue);
      expect(mini, findsOneWidget);
      checked('dismiss_preserved_playback');
      await open();
    });
    await capture('audio.stop_button', 'Stop clears the track and disables idle transport controls', () async {
      await ui.tap(icon(PhonoliteIcons.square));
      await ui.waitUntil(() => controller.playbackState.track == null, description: 'stopped and empty player');
      expect(controller.playbackState.isPlaying, isFalse);
      final transport = within(
        sheet,
        find.byWidgetPredicate(
          (w) =>
              w is ObsidianHudIconButton &&
              [PhonoliteIcons.square, PhonoliteIcons.skipBack, PhonoliteIcons.skipForward].contains(w.icon),
        ),
      );
      for (final button in ui.tester.widgetList<ObsidianHudIconButton>(transport)) {
        expect(button.onPressed, isNull);
      }
      await ui.tap(icon(Icons.play_arrow));
      expect(controller.playbackState.track, isNull);
      checked('stop_and_idle_transport_disabled');
    });
    // Inspect encoded packets after stopping playback, keeping the two
    // observations separate and avoiding competing live output streams.
    final wireResults = <String, Map<String, Object?>>{};
    for (final quality in qualityTargets.keys) {
      await capture(
        'audio.wire_$quality',
        'Inspect real $quality Opus header and two seconds of encoded packets',
        () async {
          final wire = await inspectQualityWire(probe.lastRequest!, quality);
          wireResults[quality] = wire;
          extra['wire'] = wire;
          expect(wire['complete'], isTrue, reason: '$wire');
          final header = wire['header'] as Map;
          expect(header['bitrate_bps'], qualityTargets[quality]);
          expect(header['sample_rate'], 48000);
          expect(header['frame_ms'], 20);
          expect(header['channels'], inInclusiveRange(1, 2));
          expect(wire['packet_count'], greaterThanOrEqualTo(100));
          checked('server_target_and_packet_payload', header);
        },
      );
    }
    await capture(
      'audio.wire_ordering',
      'Encoded payload rates differ in HQ > MQ > LQ order for the same source interval',
      () async {
        final high = wireResults['high']!['encoded_payload_kbps'] as num;
        final medium = wireResults['medium']!['encoded_payload_kbps'] as num;
        final low = wireResults['low']!['encoded_payload_kbps'] as num;
        expect(high, greaterThan(medium));
        expect(medium, greaterThan(low));
        checked('encoded_payload_kbps', {'high': high, 'medium': medium, 'low': low});
      },
    );
  }

  Future<void> cleanup() async {
    final errors = <String>[];
    Future<void> attempt(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        errors.add(name);
      }
    }

    await attempt('stop playback', controller.stop);
    await attempt('restore volume', () async {
      controller.setVolume(_original.volume);
    });
    await attempt('restore quality/shuffle', () async {
      controller.updateStreamMode(_original.streamMode);
      controller.updateShuffleMode(_original.serverShuffleMode, scope: ActionScope.server);
      controller.updateShuffleMode(_original.localShuffleMode, scope: ActionScope.local);
      controller.updateShuffleMode(_original.shuffleMode, scope: _original.shuffleScope);
    });
    await attempt('restore repeat', () async {
      if (controller.playbackState.repeatMode != _original.repeatMode) {
        controller.toggleRepeatMode();
      }
      await controller.connection.updatePlaybackSettings(repeatMode: _original.repeatMode.name);
    });
    if (_likedTrack != null && _originalLike != null) {
      await attempt('restore like', () async {
        await controller.connection.setLikeState(_likedTrack!.id, _originalLike!);
      });
    }
    if (_temporaryPlaylistId != null) {
      await attempt('delete temporary playlist', () => controller.connection.deletePlaylist(_temporaryPlaylistId!));
    }
    output['cleanup_errors'] = errors;
    expect(errors, isEmpty, reason: 'Original state must be restored');
  }
}

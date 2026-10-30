import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_output_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_slider_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_viewport.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/accessibility_update_binding.dart';
import '../support/widget_test_helpers.dart';

void main() {
  final binding = AccessibilityUpdateBinding();

  setUp(() {
    configureTestFonts();
    binding.resetAccessibilityTree();

    final semantics = binding.ensureSemantics();

    addTearDown(semantics.dispose);
  });

  testWidgets('enabling a restored seek slider initializes all popup nodes', (tester) async {
    var enabled = false;
    var value = 0.5;

    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        theme: ObsidianTheme.build(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 48,
            child: ObsidianSliderScope(
              child: Slider(value: value, onChanged: enabled ? (_) {} : null),
            ),
          ),
        ),
      ),
    );

    await show();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    enabled = true;
    await show();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final enabledState = tester.state(find.byType(Slider));

    value = 0.75;
    await show();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(Slider)), same(enabledState));
    expect(tester.takeException(), isNull);
    enabled = false;
    await show();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final wholeBar in [false, true]) {
    for (final local in [false, true]) {
      for (final width in [1280.0, 430.0]) {
        testWidgets(
          '${wholeBar ? 'player' : 'output'} startup restores ${local ? 'local' : 'server'} track at $width',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 720);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);

            var state = _idle();

            Future<void> show() => tester.pumpWidget(
              MaterialApp(
                theme: ObsidianTheme.build(),
                themeAnimationStyle: AnimationStyle.noAnimation,
                builder: (_, child) => TooltipVisibility(visible: false, child: ObsidianViewport(child: child!)),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: wholeBar
                        ? _bar(state)
                        : SizedBox(width: width > 600 ? 350 : 320, height: 160, child: _output(state)),
                  ),
                ),
              ),
            );

            await show();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            state = state.copyWith(
              track: Track(
                id: 'restored',
                title: 'Restored track',
                artist: 'Artist',
                album: 'Album',
                durationMs: 60000,
                liked: false,
                inPlaylists: false,
              ),
              duration: const Duration(minutes: 1),
              position: const Duration(seconds: 12),
              volume: 0.8,
              isLocalPlayback: local,
              bitrateKbps: local ? null : 320,
            );
            await show();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            state = state.copyWith(track: null);
            await show();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.windows),
        );
      }
    }
  }
}

PlaybackState _idle() => PlaybackState(
  track: null,
  isPlaying: false,
  isLoading: false,
  position: Duration.zero,
  duration: Duration.zero,
  bufferRatio: 0,
  volume: 1,
  shuffleMode: ShuffleMode.off,
  shuffleScope: ActionScope.server,
  repeatMode: PlaybackRepeatMode.off,
  streamMode: StreamMode.auto,
  bitrateKbps: null,
  streamConnected: false,
  streamRttMs: null,
  queueSource: PlaybackQueueSource.none,
  queueSourcePlaylistId: null,
  localPlaybackSource: LocalPlaybackSource.none,
  isLocalPlayback: false,
);

Widget _output(PlaybackState state) => PlaybackOutputZone(
  state: state,
  compact: false,
  onStreamModeChanged: (_) {},
  onVolumeChanged: (_) {},
  onToggleMute: _noop,
  onToggleLike: _noop,
  onAddToPlaylist: _noop,
  onShowDevicePicker: _noop,
);

Widget _bar(PlaybackState state) => NowPlayingBar(
  state: state,
  onOpenAlbum: _noop,
  onPlayPause: _noop,
  onNext: _noop,
  onPrev: _noop,
  onStop: _noop,
  onSeek: (_) {},
  onSeekPreview: (_) {},
  onShuffleChanged: (_, {scope}) {},
  onToggleRepeat: _noop,
  onStreamModeChanged: (_) {},
  onVolumeChanged: (_) {},
  onToggleMute: _noop,
  onToggleLike: _noop,
);

void _noop() {}

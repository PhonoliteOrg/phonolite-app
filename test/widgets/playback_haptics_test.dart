import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final expanded in [false, true]) {
    final player = expanded ? 'expanded tray' : 'compact player';
    testWidgets(
      '$player sends one light iOS haptic for each play and pause press',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => AppController(
            connection: ServerConnection(baseUrl: 'http://unused.test/api'),
          ),
        ))!;
        final haptics = _captureHaptics(tester);
        var toggles = 0;
        var skips = 0;
        var state = _state(controller);
        try {
          await _pump(
            tester,
            controller,
            StatefulBuilder(
              builder: (context, setState) => _player(
                expanded: expanded,
                state: state,
                onPlayPause: () {
                  toggles++;
                  setState(
                    () => state = state.copyWith(isPlaying: !state.isPlaying),
                  );
                },
                onNext: () => skips++,
              ),
            ),
          );
          await tester.tap(find.byIcon(Icons.play_arrow));
          await tester.pump();
          expect(toggles, 1);
          expect(find.byIcon(Icons.pause), findsOneWidget);
          await tester.tap(find.byIcon(Icons.pause));
          await tester.pump();
          expect(toggles, 2);
          expect(find.byIcon(Icons.play_arrow), findsOneWidget);

          if (!expanded) {
            // The compact player's padding also belongs to its play target.
            final paddingTarget = find.byWidgetPredicate(
              (widget) =>
                  widget is GestureDetector &&
                  widget.behavior == HitTestBehavior.opaque &&
                  widget.child is Padding,
            );
            final rect = tester.getRect(paddingTarget);
            await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
            await tester.pump();
            expect(toggles, 3);
          }

          final expectedHaptics = defaultTargetPlatform == TargetPlatform.iOS
              ? List.filled(toggles, 'HapticFeedbackType.lightImpact')
              : <String>[];
          expect(haptics, expectedHaptics);
          await tester.tap(find.byIcon(PhonoliteIcons.skipForward));
          await tester.pump();
          expect(skips, 1);
          expect(haptics, [
            ...expectedHaptics,
            if (defaultTargetPlatform == TargetPlatform.iOS)
              'HapticFeedbackType.lightImpact',
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(controller.close);
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );

    for (final loading in [false, true]) {
      testWidgets(
        '$player cannot toggle when ${loading ? 'loading' : 'idle'} disables play',
        (tester) async {
          final controller = (await tester.runAsync(
            () async => AppController(
              connection: ServerConnection(
                baseUrl: 'http://unused.test/api',
              ),
            ),
          ))!;
          final haptics = _captureHaptics(tester);
          var toggles = 0;
          final state = loading
              ? _state(controller).copyWith(isLoading: true)
              : controller.playbackState;
          try {
            await _pump(
              tester,
              controller,
              _player(
                expanded: expanded,
                state: state,
                onPlayPause: () => toggles++,
                onNext: () {},
              ),
            );
            await tester.tap(
              find.byIcon(Icons.play_arrow),
              warnIfMissed: false,
            );
            await tester.pump();
            expect(toggles, 0);
            // Tapping disabled play in the compact bar activates its enabled
            // parent row, which opens the tray and has its own feedback.
            expect(
              haptics,
              expanded ? <String>[] : ['HapticFeedbackType.lightImpact'],
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(controller.close);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}

List<String> _captureHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

PlaybackState _state(AppController controller) =>
    controller.playbackState.copyWith(
      track: Track(
        id: 'song',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 60000,
        liked: false,
        inPlaylists: false,
      ),
      duration: const Duration(minutes: 1),
      isLocalPlayback: true,
      queueSource: PlaybackQueueSource.offline,
      localPlaybackSource: LocalPlaybackSource.library,
    );

Widget _player({
  required bool expanded,
  required PlaybackState state,
  required VoidCallback onPlayPause,
  required VoidCallback onNext,
}) => expanded
    ? NowPlayingExpandedSheet(
        state: state,
        useNativeMobileTreatment: true,
        onOpenAlbum: null,
        onPlayPause: onPlayPause,
        onNext: onNext,
        onPrev: () {},
        onStop: () {},
        onSeek: (_) {},
        onSeekPreview: (_) {},
        onShuffleChanged: (_, {scope}) {},
        onToggleRepeat: () {},
        onStreamModeChanged: (_) {},
        onVolumeChanged: (_) {},
        onToggleMute: () {},
        onToggleLike: () {},
      )
    : NowPlayingMiniBar(
        state: state,
        onPlayPause: onPlayPause,
        onNext: onNext,
        onExpand: () {},
      );

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  Widget player,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    AppScope(controller: controller, child: wrapInTestApp(player)),
  );
  await tester.pump();
}

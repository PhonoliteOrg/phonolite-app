import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_command_zone.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/marquee_text.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

import '../support/widget_test_helpers.dart';

void main() {
  testWidgets('transport icon controls announce their action and toggle state', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller(tester);

    try {
      final state = _state(
        controller,
      ).copyWith(shuffleMode: ShuffleMode.all, repeatMode: PlaybackRepeatMode.one, isPlaying: true);
      await tester.pumpWidget(
        wrapInTestApp(
          Center(
            child: PlaybackCommandZone(
              state: state,
              onPlayPause: () {},
              onPrev: () {},
              onNext: () {},
              onStop: () {},
              onShuffle: () {},
              onRepeat: () {},
            ),
          ),
        ),
      );

      for (final label in ['Previous track', 'Pause', 'Stop', 'Next track']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }

      expect(
        tester.getSemantics(find.bySemanticsLabel('Shuffle: Whole Library')),
        isSemantics(label: 'Shuffle: Whole Library', isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Repeat: Current Track')),
        isSemantics(label: 'Repeat: Current Track', isButton: true, hasToggledState: true, isToggled: true),
      );

      await tester.pumpWidget(wrapInTestApp(Center(child: LikeIconButton(isLiked: true, onPressed: () {}))));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Unlike')),
        isSemantics(label: 'Unlike', isButton: true, hasToggledState: true, isToggled: true),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
      semantics.dispose();
    }
  });

  testWidgets('marquee stays a single static label when animations are disabled', (tester) async {
    const title = 'A very long track title that cannot fit inside the narrow player column';
    final semantics = tester.ensureSemantics();

    Widget marquee({required bool disableAnimations}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            child: MarqueeText(text: title, style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );

    await tester.pumpWidget(marquee(disableAnimations: true));
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(Scrollable), findsNothing);
    expect(find.text(title), findsOneWidget);
    expect(tester.widget<Text>(find.text(title)).overflow, TextOverflow.ellipsis);

    // When it scrolls, the looping copy is visual only and is announced once.
    await tester.pumpWidget(marquee(disableAnimations: false));
    await tester.pump();

    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text(title), findsNWidgets(2));
    expect(find.bySemanticsLabel(title), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('mini bar grows with large text instead of clipping', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    try {
      late double reservedHeight;
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: wrapInTestApp(
            MediaQuery.withClampedTextScaling(
              minScaleFactor: 2,
              maxScaleFactor: 2,
              child: Builder(
                builder: (context) {
                  reservedHeight = NowPlayingMiniBar.heightOf(context);

                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: NowPlayingMiniBar(
                      state: _state(controller),
                      onPlayPause: () {},
                      onNext: () {},
                      onExpand: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(reservedHeight, greaterThan(72));
      expect(find.bySemanticsLabel('Next song'), findsOneWidget);
      expect(find.bySemanticsLabel('Play'), findsOneWidget);

      final title = tester.getRect(find.text('Song').first);
      final bar = tester.getRect(find.byType(NowPlayingMiniBar));
      expect(title.top, greaterThanOrEqualTo(bar.top));
      expect(title.bottom, lessThanOrEqualTo(bar.bottom));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
      semantics.dispose();
    }
  });
}

Future<AppController> _controller(WidgetTester tester) async {
  return (await tester.runAsync(
    () async => AppController(connection: ServerConnection(baseUrl: 'http://unused.test/api')),
  ))!;
}

PlaybackState _state(AppController controller) => controller.playbackState.copyWith(
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

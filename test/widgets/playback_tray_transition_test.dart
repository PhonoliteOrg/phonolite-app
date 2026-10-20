import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('dragging the tray reuses its unchanged foreground paint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugOnProfilePaint = null;
    });
    final controller = (await tester.runAsync(
      () async => _PlayingController(),
    ))!;
    try {
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.iOS),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNowPlayingExpandedSheet(context),
                child: const Text('Open player'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open player'));
      await tester.pumpAndSettle();
      final foreground = tester.renderObject(
        find
            .descendant(
              of: find.byType(NowPlayingExpandedSheet),
              matching: find.byType(Column),
            )
            .first,
      );
      var foregroundPaints = 0;
      debugOnProfilePaint = (object) {
        if (identical(object, foreground)) foregroundPaints++;
      };
      final tray = tester.getRect(find.byType(NowPlayingExpandedSheet));
      final drag = await tester.startGesture(
        Offset(tray.center.dx, tray.top + 15),
      );
      for (var step = 0; step < 8; step++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.getTopLeft(find.byType(NowPlayingExpandedSheet)).dy,
        greaterThan(tray.top + 100),
      );
      expect(
        foregroundPaints,
        lessThanOrEqualTo(1),
        reason:
            'Allow the initial interaction update, then reuse foreground paint '
            'throughout the drag.',
      );
      // A live scrubber should keep advancing without invalidating the artwork
      // and controls around it, even while the tray is held partway down.
      foregroundPaints = 0;
      final previousPosition = tester.widget<Slider>(find.byType(Slider)).value;
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(previousPosition),
      );
      expect(foregroundPaints, 0);
      debugOnProfilePaint = null;
      await drag.up();
      await tester.pumpAndSettle();
      // Dismiss fully after the short drag snaps back to the expanded position.
      await tester.fling(
        find.byType(NowPlayingExpandedSheet),
        const Offset(0, 650),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingExpandedSheet), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnProfilePaint = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(controller.close);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

class _PlayingController extends AppController {
  _PlayingController()
    : super(
        connection: ServerConnection(baseUrl: 'http://server.test/api/v1'),
      ) {
    _snapshot = super.playbackState.copyWith(
      track: Track(
        id: 'song',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 60000,
        liked: false,
        inPlaylists: false,
      ),
      isPlaying: true,
      isLocalPlayback: true,
      duration: const Duration(minutes: 1),
      position: const Duration(seconds: 5),
    );
  }

  PlaybackState? _snapshot;

  @override
  PlaybackState get playbackState => _snapshot ?? super.playbackState;
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final layout in [
    (width: 1280.0, mini: false),
    (width: 780.0, mini: true),
    (width: 430.0, mini: true),
  ]) {
    testWidgets(
      '${layout.width}px player keeps artwork bounds through metadata and image loading',
      (tester) async {
        // Create and close real resources in the same asynchronous zone; a
        // completed future created in the widget's fake clock can otherwise
        // stall runAsync teardown while that clock is suspended.
        final controller = (await tester.runAsync(
          () async => AppController(
            connection: ServerConnection(baseUrl: 'http://server.test/api'),
          ),
        ))!;
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('phonolite-artwork-layout-'),
        );
        final file = File('${directory!.path}/cover.png');
        tester.view.physicalSize = Size(layout.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        try {
          await tester.runAsync(() async {
            // A 24x12 image checks that intrinsic image dimensions never alter
            // the square reserved by the player.
            await file.writeAsBytes(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAABgAAAAMCAYAAAB4MH11AAAAAXNSR0IArs4c6Q'
                'AAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAjSURBVDhP'
                'Y/jvyvCflpgBXYDaeNQCgnjUAoJ41AKCmOYWAABeY4t/F1p0IgAAAABJRU5ErkJggg==',
              ),
            );
          });

          Future<void> pump(Track? track) => tester.pumpWidget(
            AppScope(
              controller: controller,
              child: wrapInTestApp(
                ObsidianScale(
                  scale: ObsidianScale.compute(layout.width),
                  child: layout.mini
                      ? NowPlayingMiniBar(
                          state: controller.playbackState.copyWith(
                            track: track,
                          ),
                          onPlayPause: _noop,
                          onNext: _noop,
                          onExpand: _noop,
                        )
                      : NowPlayingBar(
                          state: controller.playbackState.copyWith(
                            track: track,
                          ),
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
                          onToggleLike: _noop,
                        ),
                ),
              ),
            ),
          );

          Rect artRect() {
            final player = find.byType(
              layout.mini ? NowPlayingMiniBar : NowPlayingBar,
            );
            // The mini player uses a music icon before any album is selected.
            final artwork = find.descendant(
              of: player,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is ClipRect &&
                    (widget.child is SizedBox || widget.child is Container),
              ),
            );
            return tester.getRect(artwork);
          }

          await pump(null);
          final idle = artRect();
          final track = Track(
            id: 'song',
            title: 'Song',
            artist: 'Artist',
            album: 'Album',
            durationMs: 60000,
            liked: false,
            inPlaylists: false,
          );
          await pump(track);
          expect(artRect(), idle);

          await pump(track.copyWith(albumId: 'album', albumArtPath: file.path));
          expect(artRect(), idle);
          expect(find.byType(RawImage), findsNothing);

          for (
            var attempt = 0;
            attempt < 20 && find.byType(RawImage).evaluate().isEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(find.byType(RawImage), findsOneWidget);
          expect(artRect(), idle);
          expect(tester.getRect(find.byType(RawImage)), idle);
          expect(idle.width, closeTo(idle.height, 0.001));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(() async {
            await controller.close();
            await file.delete();
            await directory.delete();
          });
        }
      },
    );
  }
}

void _noop() {}

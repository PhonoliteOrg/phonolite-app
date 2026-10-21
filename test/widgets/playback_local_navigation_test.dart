import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/pages/auth/login_page.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/pages/library/artist_detail_screen.dart';
import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/navigation/desktop_playback_shortcuts.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';
import 'package:phonolite_app/ui/shell/adaptive_scaffold.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('session invalidation opens sign-in once in settings', (tester) async {
    final controller = (await tester.runAsync(() async => _SignInController()))!;
    try {
      await _pumpHome(tester, controller, width: 1280);
      controller.invalidate();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('SIGN IN'), findsNWidgets(2));
      controller.invalidate();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(LoginPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(controller.authState.isAuthorized, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
      await controller.authUpdates.close();
    }
  });

  testWidgets('system back bubbles at the active tab root and requests app exit', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      expect(await root.maybePop(), isFalse);
      var exits = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') {
          exits++;
        }

        return null;
      });

      try {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(exits, 1);
        expect(find.byType(HomePage), findsOneWidget);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });
  });

  testWidgets('system back consumes the active nested stack without popping Home', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      final result = tab.push<String>(
        MaterialPageRoute<String>(builder: (_) => const Scaffold(body: Text('Nested back target'))),
      );
      await tester.pumpAndSettle();

      expect(await root.maybePop('root result'), isTrue);
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(find.text('Nested back target'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(await root.maybePop(), isFalse);
    });
  });

  testWidgets('back consumes a newly pushed nested route before the next frame', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      final result = tab.push<String>(
        MaterialPageRoute<String>(builder: (_) => const Scaffold(body: Text('Immediate nested target'))),
      );

      expect(await root.maybePop(), isTrue);
      expect(await result, isNull);
      await tester.pumpAndSettle();

      expect(find.text('Immediate nested target'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  testWidgets('a second back request bubbles after a nested pop without another frame', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      unawaited(
        tab.push<void>(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Double back target')))),
      );
      await tester.pumpAndSettle();

      expect(await root.maybePop(), isTrue);
      expect(await root.maybePop(), isFalse);
      await tester.pumpAndSettle();

      expect(find.text('Double back target'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  testWidgets('inactive retained stacks do not intercept another tab root back', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      unawaited(tab.push<void>(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Retained target')))));
      await tester.pumpAndSettle();
      await _selectTab(tester, 1);

      expect(await root.maybePop(), isFalse);
      expect(tab.canPop(), isTrue);

      await _selectTab(tester, 0);
      expect(find.text('Retained target'), findsOneWidget);
      expect(await root.maybePop(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Retained target'), findsNothing);
    });
  });

  testWidgets('back dismisses unnamed nested popups before returning to the tab root', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(LibraryPage)),
          useRootNavigator: false,
          builder: (_) => const AlertDialog(content: Text('Nested back dialog')),
        ),
      );
      await tester.pumpAndSettle();

      expect(await root.maybePop(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Nested back dialog'), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(await root.maybePop(), isFalse);
    });
  });

  testWidgets('root popups dismiss without also popping the active nested page', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      unawaited(
        tab.push<void>(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Behind root dialog')))),
      );
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('Behind root dialog')),
          builder: (_) => const AlertDialog(content: Text('Root back dialog')),
        ),
      );
      await tester.pumpAndSettle();

      expect(await root.maybePop(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Root back dialog'), findsNothing);
      expect(find.text('Behind root dialog'), findsOneWidget);
      expect(tab.canPop(), isTrue);
    });
  });

  testWidgets('back retains the existing direct-pop behavior for nested page vetoes', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      unawaited(
        tab.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const PopScope<void>(canPop: false, child: Scaffold(body: Text('Nested veto target'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(await root.maybePop(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Nested veto target'), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
    });
  });

  testWidgets('a nested first-route veto does not replace the existing root bubble policy', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      final initial = ModalRoute.of(tester.element(find.byType(LibraryPage)))!;
      unawaited(
        tab.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const PopScope<void>(canPop: false, child: Scaffold(body: Text('Only nested route'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tab.removeRoute(initial);
      await tester.pumpAndSettle();

      expect(tab.canPop(), isFalse);
      expect(await root.maybePop(), isFalse);
      expect(find.text('Only nested route'), findsOneWidget);
    });
  });

  testWidgets('back consumes nested local history before bubbling at Home', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      var removed = 0;
      final route = ModalRoute.of(tester.element(find.byType(LibraryPage)))!;
      route.addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => removed++));
      await tester.pumpAndSettle();

      expect(await root.maybePop(), isTrue);
      await tester.pumpAndSettle();

      expect(removed, 1);
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(await root.maybePop(), isFalse);
    });
  });

  testWidgets('Home can pop from a non-first outer route without recursive navigation', (tester) async {
    await _withHomeNavigation(tester, (root, tab) async {
      final original = ModalRoute.of(tester.element(find.byType(HomePage)));
      final result = root.push<String>(MaterialPageRoute<String>(builder: (_) => const HomePage()));
      await tester.pumpAndSettle();

      expect(root.canPop(), isTrue);
      expect(await root.maybePop('outer result'), isTrue);
      await tester.pumpAndSettle();

      expect(await result, 'outer result');
      expect(ModalRoute.of(tester.element(find.byType(HomePage))), same(original));
      expect(root.canPop(), isFalse);
    });
  });

  for (final width in [430.0, 1280.0]) {
    for (final connected in [false, true]) {
      for (final kind in ['artist', 'track']) {
        testWidgets('stats $kind opens the library stack (connected: $connected, width: $width)', (tester) async {
          final controller = (await tester.runAsync(() async => _StatsController(connected: connected)))!;
          try {
            await _pumpHome(tester, controller, width: width);
            await _selectTab(tester, 3);
            final tile = find.byKey(ValueKey('stats-$kind-${kind == 'artist' ? 'artist' : _track.id}'));
            await tester.ensureVisible(tile);
            await tester.pumpAndSettle();
            final statsRoute = ModalRoute.of(tester.element(tile))!;
            await tester.tap(tile);
            await tester.pumpAndSettle();

            expect(tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex, 0);
            final artistType = connected ? ArtistDetailScreen : LocalArtistDetailScreen;
            final albumType = connected ? AlbumDetailScreen : LocalAlbumDetailScreen;
            final destination = find.byType(kind == 'track' ? albumType : artistType);
            expect(destination, findsOneWidget);
            final route = ModalRoute.of(tester.element(destination))!;
            final source = connected ? 'server' : 'local';
            expect(route.settings.name, '/library/$source/${kind == 'track' ? 'album/album' : 'artist/artist'}');
            expect(route.navigator, isNot(same(statsRoute.navigator)));
            expect(controller.playbackState.track, isNull);

            if (kind == 'track') {
              await tester.tap(find.text('BACK TO ARTIST'));
              await tester.pumpAndSettle();
              expect(find.byType(artistType), findsOneWidget);
            }
            await tester.tap(find.text('BACK TO LIBRARY'));
            await tester.pumpAndSettle();
            expect(find.byType(LibraryPage), findsOneWidget);
            await _selectTab(tester, 3);
            expect(ModalRoute.of(tester.element(tile)), same(statsRoute));
            if (!connected) {
              expect(controller.serverMetadataRequests, isEmpty);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, controller);
          }
        });
      }
    }
  }

  for (final kind in ['artist', 'track']) {
    testWidgets('stats $kind reports unavailable library items', (tester) async {
      final controller = (await tester.runAsync(() async => _StatsController(connected: true, downloads: [])))!;
      (controller.connection as _Connection).metadataUnavailable = true;
      try {
        await _pumpHome(tester, controller, width: 1280);
        await _selectTab(tester, 3);
        final tile = find.byKey(ValueKey('stats-$kind-${kind == 'artist' ? 'artist' : _track.id}'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.text('This $kind is not available in the library.'), findsOneWidget);
        expect(tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex, 3);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    });
  }

  for (final sameServer in [false, true]) {
    testWidgets('stats track fallback respects catalog identity ($sameServer)', (tester) async {
      final controller = (await tester.runAsync(
        () async => _StatsController(
          connected: true,
          downloads: [
            _track.copyWith(
              id: 'download-id',
              serverTrackId: _track.id,
              serverBaseUrl: sameServer ? 'http://server.test/api' : 'http://other.test/api',
            ),
          ],
        ),
      ))!;
      (controller.connection as _Connection).metadataUnavailable = true;
      try {
        await _pumpHome(tester, controller, width: 1280);
        await _selectTab(tester, 3);
        final tile = find.byKey(ValueKey('stats-track-${_track.id}'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        if (sameServer) {
          _expectLocalAlbum(tester, 'download-id');
          await _expectAlbumBackStack(tester);
        } else {
          expect(find.byType(LocalAlbumDetailScreen), findsNothing);
          expect(find.text('This track is not available in the library.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    });
  }

  testWidgets('stats ignores repeated taps and late responses after a tab switch', (tester) async {
    final controller = (await tester.runAsync(() async => _StatsController(connected: true)))!;
    final connection = controller.connection as _Connection;
    connection.pendingTrack = Completer<Track>();
    try {
      await _pumpHome(tester, controller, width: 1280);
      await _selectTab(tester, 3);
      final tile = find.byKey(ValueKey('stats-track-${_track.id}'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.tap(tile);
      expect(connection.metadataRequests, ['track:${_track.id}']);
      await _selectTab(tester, 1);
      connection.pendingTrack!.complete(_track);
      await tester.pumpAndSettle();
      expect(tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex, 1);
      expect(find.byType(AlbumDetailScreen), findsNothing);
      expect(connection.metadataRequests, ['track:${_track.id}']);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });

  testWidgets(
    'desktop Space toggles the current playback state across all tabs',
    (tester) async {
      final controller = (await tester.runAsync(() async => _PlaybackController()))!;
      try {
        await _pumpHome(tester, controller, width: 1280);
        // The second press must use the latest controller state even before
        // the player has rebuilt or received a stream update.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(controller.pauseRequests, [false, true]);
        for (var tab = 0; tab < 5; tab++) {
          tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(tab);
          await tester.pumpAndSettle();
          final wasPlaying = controller.playbackState.isPlaying;
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          expect(controller.pauseRequests.last, wasPlaying);
          expect(controller.playbackState.isPlaying, !wasPlaying);
        }
        expect(controller.pauseRequests, hasLength(7));
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}),
  );

  for (final origin in [0, 1]) {
    testWidgets(
      'album stack replacement transitions from the visible screen in tab $origin',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => _Controller(connected: false, tracks: [_track], playing: _track),
        ))!;
        final boundaryKey = GlobalKey();
        try {
          await _pumpHome(tester, controller, width: 1280, boundaryKey: boundaryKey);
          tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(origin);
          await tester.pumpAndSettle();
          final navigator = Navigator.of(tester.element(find.byType(origin == 0 ? LibraryPage : PlaylistsPage)));
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Center(
                  child: ColoredBox(color: Color(0xFF00FFFF), child: SizedBox(width: 100, height: 100)),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final before = await _cyanPixels(tester, boundaryKey);
          expect(before, greaterThan(0));
          await tester.tap(find.descendant(of: find.byType(NowPlayingBar), matching: find.byType(AlbumArt)));
          await tester.pump();
          expect(
            await _cyanPixels(tester, boundaryKey),
            before,
            reason: 'The first frame must retain the actual outgoing screen',
          );
          expect(
            find.byType(LocalArtistDetailScreen),
            findsNothing,
            reason: 'The artist is back-stack state, not an intermediate visible page',
          );
          await tester.pump(const Duration(milliseconds: 60));
          expect(await _cyanPixels(tester, boundaryKey), 0);
          expect(find.byType(LocalArtistDetailScreen), findsNothing);
          await tester.pumpAndSettle();
          _expectLocalAlbum(tester, _track.id);
          await _expectAlbumBackStack(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final isLocal in [true, false]) {
    testWidgets(
      '${isLocal ? 'local' : 'server'} player artwork opens the Library artist-album stack with one transition',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => _Controller(connected: !isLocal, tracks: [_track], playing: _track, localPlayback: isLocal),
        ))!;
        try {
          await _pumpHome(tester, controller, width: 1280);
          final oldLibraryRoute = ModalRoute.of(tester.element(find.byType(LibraryPage)))!;
          oldLibraryRoute.navigator!.push<void>(
            MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other Library detail'))),
          );
          await tester.pumpAndSettle();
          tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(1);
          await tester.pumpAndSettle();
          final rootRoute = ModalRoute.of(tester.element(find.byType(PlaylistsPage)))!;
          final previousRoute = MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Current detail page')),
          );
          rootRoute.navigator!.push<void>(previousRoute);
          await tester.pumpAndSettle();

          await tester.tap(find.descendant(of: find.byType(NowPlayingBar), matching: find.byType(AlbumArt)));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
          expect(
            tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex,
            0,
            reason: 'Albums belong to the existing Library navigator',
          );
          final albumRoute = ModalRoute.of(
            tester.element(find.byType(isLocal ? LocalAlbumDetailScreen : AlbumDetailScreen)),
          )!;
          expect(albumRoute, isA<MaterialPageRoute<void>>());
          expect(albumRoute.animation!.value, 1, reason: 'Only the visible stack transition should animate');
          final libraryRoute = ModalRoute.of(tester.element(find.byType(LibraryPage, skipOffstage: false)))!;
          expect(albumRoute.navigator, same(libraryRoute.navigator));
          final artistFinder = find.byType(isLocal ? LocalArtistDetailScreen : ArtistDetailScreen, skipOffstage: false);
          final artistRoute = ModalRoute.of(tester.element(artistFinder))!;
          expect(artistRoute.navigator, same(libraryRoute.navigator));
          expect(artistRoute.animation!.status, AnimationStatus.completed);
          expect(artistRoute.animation!.value, 1);
          await tester.pumpAndSettle();

          // Clicking the same cover again must not add duplicate album routes.
          await _tapDesktopTitle(tester);
          expect(
            ModalRoute.of(tester.element(find.byType(isLocal ? LocalAlbumDetailScreen : AlbumDetailScreen))),
            same(albumRoute),
          );

          await tester.tap(find.text('BACK TO ARTIST'));
          await tester.pumpAndSettle();
          expect(artistRoute.isCurrent, isTrue);
          expect(find.byType(isLocal ? LocalArtistDetailScreen : ArtistDetailScreen), findsOneWidget);
          await tester.tap(find.text('BACK TO LIBRARY'));
          await tester.pumpAndSettle();
          expect(libraryRoute.isCurrent, isTrue);
          expect(find.byType(LibraryPage), findsOneWidget);

          // The other tab keeps its own stack; no album is pushed into it.
          tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(1);
          await tester.pumpAndSettle();
          expect(previousRoute.isCurrent, isTrue);
          expect(find.text('Current detail page'), findsOneWidget);
          previousRoute.navigator!.pop();
          await tester.pumpAndSettle();
          expect(rootRoute.isCurrent, isTrue);
          expect(find.byType(PlaylistsPage), findsOneWidget);
          expect(controller.serverMetadataRequests, isLocal ? isEmpty : containsAll(['album:album', 'artist:artist']));
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'player artwork reuses the normal Library artist and album routes',
    (tester) async {
      final controller = (await tester.runAsync(
        () async => _Controller(connected: false, tracks: [_track], playing: _track),
      ))!;
      try {
        await _pumpHome(tester, controller, width: 1280);
        await tester.tap(find.byType(ArtistCard));
        await tester.pumpAndSettle();
        final artistRoute = ModalRoute.of(tester.element(find.byType(LocalArtistDetailScreen)))!;
        await tester.tap(find.byType(AlbumCard));
        await tester.pumpAndSettle();
        final albumRoute = ModalRoute.of(tester.element(find.byType(LocalAlbumDetailScreen)))!;
        await _tapDesktopTitle(tester);
        expect(ModalRoute.of(tester.element(find.byType(LocalAlbumDetailScreen))), same(albumRoute));
        await tester.tap(find.text('BACK TO ARTIST'));
        await tester.pumpAndSettle();
        expect(artistRoute.isCurrent, isTrue);

        await _tapDesktopTitle(tester);
        _expectLocalAlbum(tester, _track.id);
        await tester.tap(find.text('BACK TO ARTIST'));
        await tester.pumpAndSettle();
        expect(artistRoute.isCurrent, isTrue);
        await tester.tap(find.text('BACK TO LIBRARY'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);
        expect(controller.serverMetadataRequests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'desktop side buttons navigate the real album, artist, and library menus',
    (tester) async {
      final controller = (await tester.runAsync(
        () async => _Controller(connected: false, tracks: [_track], playing: _track),
      ))!;
      try {
        await _pumpHome(tester, controller, width: 1280);
        await tester.tap(find.byType(ArtistCard));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AlbumCard));
        await tester.pumpAndSettle();
        _expectLocalAlbum(tester, _track.id);

        Future<void> click(int buttons) async {
          final mouse = await tester.startGesture(
            const Offset(10, 10),
            kind: PointerDeviceKind.mouse,
            buttons: buttons,
          );
          await mouse.up();
          await tester.pumpAndSettle();
        }

        await click(kBackMouseButton);
        expect(find.byType(LocalArtistDetailScreen), findsOneWidget);
        await click(kBackMouseButton);
        expect(find.byType(LibraryPage), findsOneWidget);
        await click(kBackMouseButton);
        expect(find.byType(LibraryPage), findsOneWidget);
        await click(kForwardMouseButton);
        expect(find.byType(LocalArtistDetailScreen), findsOneWidget);
        await click(kForwardMouseButton);
        _expectLocalAlbum(tester, _track.id);

        // Existing Back buttons feed the same forward history.
        await tester.tap(find.text('BACK TO ARTIST'));
        await tester.pumpAndSettle();
        await click(kForwardMouseButton);
        _expectLocalAlbum(tester, _track.id);
        expect(controller.serverMetadataRequests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}),
  );

  for (final scenario in const [
    (width: 1280.0, connected: false, alias: false),
    (width: 980.0, connected: true, alias: true),
  ]) {
    testWidgets(
      'local player opens the Library artist-album stack at ${scenario.width}px, connected=${scenario.connected}',
      (tester) async {
        final downloaded = _track.copyWith(
          albumId: scenario.alias ? null : 'album',
          serverTrackId: scenario.alias ? 'server-track' : null,
          artistId: scenario.alias ? 'artist' : 'guest',
          artist: scenario.alias ? 'Alice' : 'Guest Singer',
          // Downloaded album metadata can name a different main artist.
          offlineAlbum: scenario.alias
              ? null
              : Album(id: 'album', title: 'First Light', artist: 'Alice', artistId: 'artist', trackCount: 1),
        );
        final controller = (await tester.runAsync(
          () async => _Controller(
            connected: scenario.connected,
            tracks: [downloaded],
            playing: scenario.alias ? downloaded.copyWith(id: 'server-track', serverTrackId: null) : downloaded,
          ),
        ))!;
        try {
          await _pumpHome(tester, controller, width: scenario.width);
          // Player albums use the Library stack even from another tab.
          final scaffold = tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold));
          scaffold.onDestinationSelected(1);
          await tester.pumpAndSettle();
          await _tapDesktopTitle(tester);
          _expectLocalAlbum(tester, downloaded.id);
          expect(tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex, 0);

          // Re-entering the same details does not accumulate duplicate routes.
          await _tapDesktopTitle(tester);
          _expectLocalAlbum(tester, downloaded.id);
          await _expectAlbumBackStack(tester);
          expect(controller.serverMetadataRequests, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final target in const ['artwork', 'subtitle']) {
    testWidgets(
      'local mobile expanded $target opens details and dismisses player sheet',
      (tester) async {
        final downloaded = _track.copyWith(albumId: null);
        final controller = (await tester.runAsync(
          () async => _Controller(connected: false, tracks: [downloaded], playing: downloaded),
        ))!;
        try {
          await _pumpHome(tester, controller, width: 430);
          final mini = find.byType(NowPlayingMiniBar);
          await tester.tap(find.descendant(of: mini, matching: find.text(downloaded.title)));
          await tester.pumpAndSettle();
          final expanded = find.byType(NowPlayingExpandedSheet);
          expect(expanded, findsOneWidget);
          final details = find.descendant(
            of: expanded,
            matching: target == 'artwork'
                ? find.byType(AlbumArt)
                : find.text('${downloaded.artist} - ${downloaded.album}'),
          );
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(find.byType(NowPlayingExpandedSheet), findsNothing);
          _expectLocalAlbum(tester, downloaded.id);
          await _expectAlbumBackStack(tester);
          expect(controller.serverMetadataRequests, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final isLocal in [true, false]) {
    for (final layout in const [
      (width: 1280.0, surface: 'desktop'),
      (width: 980.0, surface: 'desktop'),
      (width: 430.0, surface: 'mini'),
      (width: 430.0, surface: 'expanded'),
    ]) {
      testWidgets(
        '${isLocal ? 'local' : 'server'} ${layout.surface} artwork opens playlist at ${layout.width}px',
        (tester) async {
          // Playlist navigation also works when album metadata is unavailable.
          final playing = _track.copyWith(albumId: null);
          final controller = (await tester.runAsync(
            () async => _Controller(
              connected: !isLocal,
              tracks: [playing],
              playing: playing,
              localPlayback: isLocal,
              fromPlaylist: true,
            ),
          ))!;
          try {
            await _pumpHome(tester, controller, width: layout.width);
            tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(2);
            await tester.pumpAndSettle();

            Future<void> tapArtwork() async {
              if (layout.surface == 'expanded') {
                await tester.tap(
                  find.descendant(of: find.byType(NowPlayingMiniBar), matching: find.text(playing.title)),
                );
                await tester.pumpAndSettle();
                expect(find.byType(NowPlayingExpandedSheet), findsOneWidget);
              }
              final player = find.byType(
                layout.surface == 'desktop'
                    ? NowPlayingBar
                    : layout.surface == 'mini'
                    ? NowPlayingMiniBar
                    : NowPlayingExpandedSheet,
              );
              await tester.tap(find.descendant(of: player, matching: find.byType(AlbumArt)));
              await tester.pumpAndSettle();
            }

            for (var attempt = 0; attempt < 2; attempt++) {
              await tapArtwork();
              final playlist = find.byType(PlaylistDetailView);
              expect(playlist, findsOneWidget);
              final details = tester.widget<PlaylistDetailView>(playlist);
              expect(details.playlistId, 'playlist');
              expect(details.isLocal, isLocal);
              expect(tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).selectedIndex, 1);
              expect(find.byType(NowPlayingExpandedSheet), findsNothing);
              expect(find.byType(LocalAlbumDetailScreen), findsNothing);
            }

            await tester.tap(find.text('BACK TO PLAYLISTS'));
            await tester.pumpAndSettle();
            expect(find.byType(PlaylistDetailView), findsNothing);
            expect(find.byType(PlaylistsPage), findsOneWidget);
            expect(controller.serverMetadataRequests, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, controller);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
    'idle player and a local track absent from the library do not navigate',
    (tester) async {
      for (final playing in <Track?>[null, _track]) {
        final controller = (await tester.runAsync(
          () async => _Controller(connected: false, tracks: [], playing: playing),
        ))!;
        try {
          await _pumpHome(tester, controller, width: 1280);
          await tester.tap(
            find.descendant(of: find.byType(NowPlayingBar), matching: find.text(playing?.title ?? 'NO TRACK PLAYING')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LocalAlbumDetailScreen), findsNothing);
          expect(find.byType(LocalArtistDetailScreen), findsNothing);
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(controller.serverMetadataRequests, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

final _track = Track(
  id: 'local-track',
  title: 'Morning',
  artist: 'Alice',
  artistId: 'artist',
  album: 'First Light',
  albumId: 'album',
  durationMs: 60000,
  liked: false,
  inPlaylists: false,
);

Future<void> _pumpHome(
  WidgetTester tester,
  _Controller controller, {
  required double width,
  GlobalKey? boundaryKey,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        builder: (_, child) => DesktopPlaybackShortcuts(
          onTogglePlayPause: () => controller.pause(controller.playbackState.isPlaying),
          child: boundaryKey == null ? child! : RepaintBoundary(key: boundaryKey, child: child!),
        ),
        theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.windows),
        home: ObsidianScale(scale: ObsidianScale.compute(width), child: const HomePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _withHomeNavigation(
  WidgetTester tester,
  Future<void> Function(NavigatorState root, NavigatorState tab) check,
) async {
  final controller = (await tester.runAsync(() async => _Controller(connected: false, tracks: [], playing: null)))!;

  try {
    await _pumpHome(tester, controller, width: 1280);

    final root = Navigator.of(tester.element(find.byType(HomePage)));
    final tab = Navigator.of(tester.element(find.byType(LibraryPage)));

    await check(root, tab);
    expect(tester.takeException(), isNull);
  } finally {
    await _dispose(tester, controller);
  }
}

Future<int> _cyanPixels(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var count = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) < 16 && bytes.getUint8(i + 1) > 40 && bytes.getUint8(i + 2) > 40) {
          count++;
        }
      }
      return count;
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _tapDesktopTitle(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NowPlayingBar), matching: find.text(_track.title)));
  await tester.pumpAndSettle();
}

void _expectLocalAlbum(WidgetTester tester, String trackId) {
  final albumScreen = find.byType(LocalAlbumDetailScreen);
  expect(albumScreen, findsOneWidget);
  final album = tester.widget<LocalAlbumDetailScreen>(albumScreen).album;
  expect(album.title, 'First Light');
  expect(album.tracks.map((track) => track.id), [trackId]);
  expect(find.descendant(of: albumScreen, matching: find.byType(TrackRowTile)), findsOneWidget);
}

Future<void> _expectAlbumBackStack(WidgetTester tester) async {
  await tester.tap(find.text('BACK TO ARTIST'));
  await tester.pumpAndSettle();
  expect(find.byType(LocalAlbumDetailScreen), findsNothing);
  final artistScreen = find.byType(LocalArtistDetailScreen);
  expect(artistScreen, findsOneWidget);
  expect(tester.widget<LocalArtistDetailScreen>(artistScreen).group.name, 'Alice');
  await tester.tap(find.text('BACK TO LIBRARY'));
  await tester.pumpAndSettle();
  expect(find.byType(LocalArtistDetailScreen), findsNothing);
  expect(find.byType(LibraryPage), findsOneWidget);
}

Future<void> _dispose(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(controller.close);
}

Future<void> _selectTab(WidgetTester tester, int index) async {
  tester.widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold)).onDestinationSelected(index);
  await tester.pumpAndSettle();
}

class _StatsController extends _Controller {
  _StatsController({required super.connected, List<Track>? downloads})
    : super(tracks: downloads ?? [_track], playing: null);

  @override
  List<Artist> get artists => [Artist(id: 'artist', name: 'Alice', albumCount: 1)];

  @override
  StatsResponse get stats => StatsResponse(
    year: 2026,
    month: null,
    totalMinutes: 42,
    topArtists: [StatsItem(id: 'artist', name: 'Alice', minutes: 42)],
    topTracks: [StatsTrack(id: _track.id, title: _track.title, artist: 'Alice', minutes: 42, plays: 3)],
    topGenres: [],
  );
}

class _Controller extends AppController {
  _Controller({
    required this.connected,
    required this.tracks,
    required Track? playing,
    bool localPlayback = true,
    bool fromPlaylist = false,
  }) : super(connection: _Connection()) {
    currentPlayback = super.playbackState.copyWith(
      track: playing,
      isPlaying: false,
      isLocalPlayback: playing != null && localPlayback,
      queueSource: playing == null
          ? PlaybackQueueSource.none
          : localPlayback
          ? PlaybackQueueSource.offline
          : fromPlaylist
          ? PlaybackQueueSource.playlist
          : PlaybackQueueSource.none,
      queueSourcePlaylistId: fromPlaylist ? 'playlist' : null,
      localPlaybackSource: playing == null || !localPlayback
          ? LocalPlaybackSource.none
          : fromPlaylist
          ? LocalPlaybackSource.playlist
          : LocalPlaybackSource.library,
    );
  }

  final bool connected;
  @override
  final List<Track> tracks;
  late final PlaybackState currentPlayback;

  List<String> get serverMetadataRequests => (connection as _Connection).metadataRequests;

  @override
  PlaybackState get playbackState => currentPlayback;

  @override
  AuthState get authState => AuthState(isAuthorized: connected, baseUrl: connection.baseUrl);

  @override
  List<Track> get offlineTracks => tracks;

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => OfflineLibrarySnapshot(
    tracks: tracks,
    artistGroups: offlineArtistGroups(tracks),
    liked: [],
    playlists: [],
    playlistTracks: [],
    revision: 1,
  );

  @override
  bool get hasMoreArtists => false;

  @override
  Future<void> loadArtists({bool refresh = false}) async {}

  @override
  Future<void> loadTracks(String albumId) async {}

  @override
  Future<void> loadArtistReleases(String artistId) async {}

  @override
  Future<void> loadPlaylists() async {}

  @override
  Future<void> loadLocalPlaylists() async {}

  @override
  List<Playlist> get playlists => [
    Playlist(id: 'playlist', name: 'Server mix', trackIds: [_track.id]),
  ];

  @override
  List<Playlist> get localPlaylists => [
    Playlist(id: 'playlist', name: 'Local mix', trackIds: [_track.id]),
  ];

  @override
  List<Track> get playlistTracks => tracks;

  @override
  List<Track> get localPlaylistTracks => tracks;

  @override
  Future<void> loadPlaylistTracks(String playlistId) async {}

  @override
  Future<void> loadLocalPlaylistTracks(String playlistId) async {}

  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> loadLocalLikedTracks() async {}

  @override
  Future<void> loadStats({int? year, int? month}) async {}
}

class _SignInController extends _Controller {
  _SignInController() : super(connected: false, tracks: [], playing: null);
  final authUpdates = StreamController<AuthState>.broadcast();
  bool invalidated = false;
  @override
  AuthState get authState => AuthState(baseUrl: connection.baseUrl,
    requiresSignIn: invalidated, error: invalidated ? 'Server keys changed. Sign in again.' : null);
  @override
  Stream<AuthState> get authStream => authUpdates.stream;
  @override
  Future<AuthCredentials?> loadSavedCredentials() async => null;
  void invalidate() {
    invalidated = true;
    authUpdates.add(authState);
  }
}

class _PlaybackController extends _Controller {
  _PlaybackController() : super(connected: false, tracks: [_track], playing: _track);

  final pauseRequests = <bool>[];
  bool _isPlaying = false;

  @override
  PlaybackState get playbackState => super.playbackState.copyWith(isPlaying: _isPlaying);

  @override
  Future<void> pause(bool paused) async {
    pauseRequests.add(paused);
    _isPlaying = !paused;
  }
}

class _Connection extends ServerConnection {
  _Connection() : super(baseUrl: 'http://server.test/api');

  final metadataRequests = <String>[];
  bool metadataUnavailable = false;
  Completer<Track>? pendingTrack;

  @override
  Future<Track> fetchTrackById(String trackId) async {
    metadataRequests.add('track:$trackId');
    if (metadataUnavailable) throw StateError('Metadata unavailable');
    return pendingTrack == null ? _track : await pendingTrack!.future;
  }

  @override
  Future<Album> fetchAlbumById(String albumId) async {
    metadataRequests.add('album:$albumId');
    if (metadataUnavailable) throw StateError('Metadata unavailable');
    return Album(id: albumId, title: 'First Light', artist: 'Alice', artistId: 'artist', trackCount: 1);
  }

  @override
  Future<Artist> fetchArtistById(String artistId) async {
    metadataRequests.add('artist:$artistId');
    if (metadataUnavailable) throw StateError('Metadata unavailable');
    return Artist(id: artistId, name: 'Alice', albumCount: 1);
  }
}

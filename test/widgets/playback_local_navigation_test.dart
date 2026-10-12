import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/home_page.dart';
import 'package:phonolite_app/pages/library_page.dart';
import 'package:phonolite_app/pages/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists_page.dart';
import 'package:phonolite_app/widgets/display/album_art.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/display/track_row_tile.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/navigation/adaptive_scaffold.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final scenario in const [
    (width: 1280.0, connected: false, alias: false),
    (width: 980.0, connected: true, alias: true),
  ]) {
    testWidgets(
      'local player opens album and artist stack at ${scenario.width}px, connected=${scenario.connected}',
      (tester) async {
        final downloaded = _track.copyWith(
          albumId: scenario.alias ? null : 'album',
          serverTrackId: scenario.alias ? 'server-track' : null,
          artistId: scenario.alias ? 'artist' : 'guest',
          artist: scenario.alias ? 'Alice' : 'Guest Singer',
          // The album's headline artist must own the back-stack, even when
          // this particular song names a different performer.
          offlineAlbum: scenario.alias
              ? null
              : Album(
                  id: 'album',
                  title: 'First Light',
                  artist: 'Alice',
                  artistId: 'artist',
                  trackCount: 1,
                ),
        );
        final controller = (await tester.runAsync(
          () async => _Controller(
            connected: scenario.connected,
            tracks: [downloaded],
            playing: scenario.alias
                ? downloaded.copyWith(id: 'server-track', serverTrackId: null)
                : downloaded,
          ),
        ))!;
        try {
          await _pumpHome(tester, controller, width: scenario.width);
          // Opening the player details also selects Library from another tab.
          final scaffold = tester.widget<AdaptiveScaffold>(
            find.byType(AdaptiveScaffold),
          );
          scaffold.onDestinationSelected(1);
          await tester.pumpAndSettle();
          await _tapDesktopTitle(tester);
          _expectLocalAlbum(tester, downloaded.id);
          expect(
            tester
                .widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold))
                .selectedIndex,
            0,
          );

          // Re-entering details resets the stack instead of accumulating routes.
          await _tapDesktopTitle(tester);
          _expectLocalAlbum(tester, downloaded.id);
          await _expectBackStack(tester);
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
          () async => _Controller(
            connected: false,
            tracks: [downloaded],
            playing: downloaded,
          ),
        ))!;
        try {
          await _pumpHome(tester, controller, width: 430);
          final mini = find.byType(NowPlayingMiniBar);
          await tester.tap(
            find.descendant(of: mini, matching: find.text(downloaded.title)),
          );
          await tester.pumpAndSettle();
          final expanded = find.byType(NowPlayingExpandedSheet);
          expect(expanded, findsOneWidget);
          await tester.tap(
            find.descendant(
              of: expanded,
              matching: target == 'artwork'
                  ? find.byType(AlbumArt)
                  : find.text('${downloaded.artist} - ${downloaded.album}'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NowPlayingExpandedSheet), findsNothing);
          _expectLocalAlbum(tester, downloaded.id);
          await _expectBackStack(tester);
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
            tester
                .widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold))
                .onDestinationSelected(2);
            await tester.pumpAndSettle();

            Future<void> tapArtwork() async {
              if (layout.surface == 'expanded') {
                await tester.tap(
                  find.descendant(
                    of: find.byType(NowPlayingMiniBar),
                    matching: find.text(playing.title),
                  ),
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
              await tester.tap(
                find.descendant(of: player, matching: find.byType(AlbumArt)),
              );
              await tester.pumpAndSettle();
            }

            for (var attempt = 0; attempt < 2; attempt++) {
              await tapArtwork();
              final playlist = find.byType(PlaylistDetailView);
              expect(playlist, findsOneWidget);
              final details = tester.widget<PlaylistDetailView>(playlist);
              expect(details.playlistId, 'playlist');
              expect(details.isLocal, isLocal);
              expect(
                tester
                    .widget<AdaptiveScaffold>(find.byType(AdaptiveScaffold))
                    .selectedIndex,
                1,
              );
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
          () async =>
              _Controller(connected: false, tracks: [], playing: playing),
        ))!;
        try {
          await _pumpHome(tester, controller, width: 1280);
          await tester.tap(
            find.descendant(
              of: find.byType(NowPlayingBar),
              matching: find.text(playing?.title ?? 'NO TRACK PLAYING'),
            ),
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
        theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.windows),
        home: ObsidianScale(
          scale: ObsidianScale.compute(width),
          child: const HomePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapDesktopTitle(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NowPlayingBar),
      matching: find.text(_track.title),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectLocalAlbum(WidgetTester tester, String trackId) {
  final albumScreen = find.byType(LocalAlbumDetailScreen);
  expect(albumScreen, findsOneWidget);
  final album = tester.widget<LocalAlbumDetailScreen>(albumScreen).album;
  expect(album.title, 'First Light');
  expect(album.tracks.map((track) => track.id), [trackId]);
  expect(
    find.descendant(of: albumScreen, matching: find.byType(TrackRowTile)),
    findsOneWidget,
  );
}

Future<void> _expectBackStack(WidgetTester tester) async {
  await tester.tap(find.text('BACK TO ARTIST'));
  await tester.pumpAndSettle();
  expect(find.byType(LocalAlbumDetailScreen), findsNothing);
  final artistScreen = find.byType(LocalArtistDetailScreen);
  expect(artistScreen, findsOneWidget);
  expect(
    tester.widget<LocalArtistDetailScreen>(artistScreen).group.name,
    'Alice',
  );
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
          : fromPlaylist && !localPlayback
          ? PlaybackQueueSource.playlist
          : PlaybackQueueSource.offline,
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

  List<String> get serverMetadataRequests =>
      (connection as _Connection).metadataRequests;

  @override
  PlaybackState get playbackState => currentPlayback;

  @override
  AuthState get authState =>
      AuthState(isAuthorized: connected, baseUrl: connection.baseUrl);

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

class _Connection extends ServerConnection {
  _Connection() : super(baseUrl: 'http://server.test/api/v1');

  final metadataRequests = <String>[];

  @override
  Future<Album> fetchAlbumById(String albumId) async {
    metadataRequests.add('album:$albumId');
    throw StateError('Local player details must use downloaded metadata');
  }

  @override
  Future<Artist> fetchArtistById(String artistId) async {
    metadataRequests.add('artist:$artistId');
    throw StateError('Local player details must use downloaded metadata');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/album_detail_screen.dart';
import 'package:phonolite_app/pages/local_album_detail_screen.dart';
import 'package:phonolite_app/widgets/display/album_hero.dart';
import 'package:phonolite_app/widgets/display/track_row_tile.dart';
import 'package:phonolite_app/widgets/display/track_sliver_list.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final isLocal in [false, true]) {
    for (final width in [430.0, 1280.0]) {
      testWidgets(
        '${isLocal ? 'local' : 'server'} partial album retains track numbers at width $width',
        (tester) async {
          final tracks = [
            _track('second', discNo: 1, trackNo: 2),
            _track('fifth', discNo: 1, trackNo: 5),
            _track('ninth', discNo: 1, trackNo: 9),
          ];
          final controller = (await tester.runAsync(
            () async => _AlbumController(isLocal: isLocal, tracks: tracks),
          ))!;
          controller.currentPlayback = controller.currentPlayback.copyWith(
            isPlaying: false,
            shuffleMode: ShuffleMode.off,
          );
          try {
            await _pump(tester, controller, isLocal: isLocal, width: width);
            for (final track in tracks) {
              final row = find.widgetWithText(TrackRowTile, track.title);
              expect(
                find.descendant(
                  of: row,
                  matching: find.text(
                    track.trackNo!.toString().padLeft(2, '0'),
                  ),
                ),
                findsOneWidget,
              );
            }
            await tester.tap(find.text('fifth'));
            await tester.pump();
            expect(controller.calls, [
              isLocal ? 'local:fifth:second,fifth,ninth' : 'server:album:fifth',
            ]);
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, controller);
          }
        },
      );

      testWidgets(
        '${isLocal ? 'local' : 'server'} album banner restarts in album order at width $width',
        (tester) async {
          final controller = (await tester.runAsync(
            () async => _AlbumController(isLocal: isLocal),
          ))!;
          try {
            await _pump(tester, controller, isLocal: isLocal, width: width);
            final banner = find.byType(AlbumHero);
            final button = find.descendant(
              of: banner,
              matching: find.byType(ObsidianHudIconButton),
            );
            expect(find.byTooltip('Play album'), findsOneWidget);
            expect(tester.getSize(button), const Size(48, 48));
            final bannerRect = tester.getRect(banner);
            final buttonRect = tester.getRect(button);
            expect(bannerRect.contains(buttonRect.topLeft), isTrue);
            expect(bannerRect.contains(buttonRect.bottomRight), isTrue);
            expect(buttonRect.top - bannerRect.top, lessThanOrEqualTo(24));
            expect(bannerRect.right - buttonRect.right, lessThanOrEqualTo(24));

            final expectedCalls = isLocal
                ? ['shuffle:local:off', 'local:first:first,second,third']
                : ['shuffle:server:off', 'server:album:null'];
            await tester.tap(button);
            await tester.pump();
            expect(controller.calls, expectedCalls);

            // This remains a play-from-start action when already playing.
            await tester.tap(button);
            await tester.pump();
            expect(controller.calls, [...expectedCalls, ...expectedCalls]);
            expect(find.byTooltip('Play album'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, controller);
          }
        },
      );
    }

    testWidgets(
      '${isLocal ? 'local' : 'server'} album cannot play an empty album',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => _AlbumController(isLocal: isLocal, empty: true),
        ))!;
        try {
          await _pump(tester, controller, isLocal: isLocal);
          final button = find.descendant(
            of: find.byType(AlbumHero),
            matching: find.byType(ObsidianHudIconButton),
          );
          expect(
            tester.widget<ObsidianHudIconButton>(button).onPressed,
            isNull,
          );
          await tester.tap(button);
          expect(controller.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
    );
  }

  for (final useAlbumNumbers in [false, true]) {
    testWidgets(
      useAlbumNumbers
          ? 'album numbers keep disc metadata and fall back for missing numbers'
          : 'playlist numbers follow playlist order instead of album numbers',
      (tester) async {
        final tracks = [
          _track('disc-one', discNo: 1, trackNo: 5),
          _track('disc-two', discNo: 2, trackNo: 2),
          _track('missing', discNo: 2, trackNo: 3).copyWith(trackNo: null),
          _track('zero', discNo: 2, trackNo: 0),
          _track('negative', discNo: 2, trackNo: -1),
        ];
        await tester.pumpWidget(
          wrapInTestApp(
            CustomScrollView(
              slivers: [
                TrackSliverList(
                  tracks: tracks,
                  isPlayingTrack: (_) => false,
                  useAlbumTrackNumbers: useAlbumNumbers,
                ),
              ],
            ),
          ),
        );
        final numbers = useAlbumNumbers
            ? ['05', '02', '03', '04', '05']
            : ['01', '02', '03', '04', '05'];
        for (var index = 0; index < tracks.length; index++) {
          final row = find.widgetWithText(TrackRowTile, tracks[index].title);
          expect(
            find.descendant(of: row, matching: find.text(numbers[index])),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('server album cannot play while its tracks are loading', (
    tester,
  ) async {
    final controller = (await tester.runAsync(
      () async => _AlbumController(loading: true),
    ))!;
    try {
      await _pump(tester, controller, isLocal: false);
      final button = find.descendant(
        of: find.byType(AlbumHero),
        matching: find.byType(ObsidianHudIconButton),
      );
      expect(tester.widget<ObsidianHudIconButton>(button).onPressed, isNull);
      expect(controller.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, controller);
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  _AlbumController controller, {
  required bool isLocal,
  double width = 1280,
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
      child: wrapInTestApp(
        isLocal
            ? LocalAlbumDetailScreen(
                album: OfflineAlbumGroup(
                  id: _album.id,
                  title: _album.title,
                  artist: _album.artist,
                  artistId: _album.artistId,
                  tracks: controller.tracks,
                ),
              )
            : AlbumDetailScreen(album: _album, artistName: _album.artist),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _dispose(WidgetTester tester, _AlbumController controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(controller.close);
}

final _album = Album(
  id: 'album',
  title: 'Album',
  artist: 'Artist',
  artistId: 'artist',
  trackCount: 3,
);
final _tracks = [
  _track('first', discNo: 1, trackNo: 1),
  _track('second', discNo: 1, trackNo: 2),
  _track('third', discNo: 2, trackNo: 1),
];

Track _track(String id, {required int discNo, required int trackNo}) => Track(
  id: id,
  title: id,
  artist: 'Artist',
  artistId: 'artist',
  album: 'Album',
  albumId: 'album',
  durationMs: 60000,
  liked: false,
  inPlaylists: false,
  discNo: discNo,
  trackNo: trackNo,
);

class _AlbumController extends AppController {
  _AlbumController({
    bool isLocal = false,
    this.empty = false,
    this.loading = false,
    List<Track>? tracks,
  }) : albumTracks = tracks ?? _tracks,
       super(connection: _AlbumConnection()) {
    currentPlayback = super.playbackState.copyWith(
      track: albumTracks.last,
      isPlaying: true,
      position: const Duration(seconds: 30),
      shuffleMode: ShuffleMode.all,
      shuffleScope: isLocal ? ActionScope.local : ActionScope.server,
    );
  }

  final bool empty;
  final bool loading;
  final List<Track> albumTracks;
  late PlaybackState currentPlayback;
  final calls = <String>[];

  @override
  AuthState get authState =>
      AuthState(isAuthorized: true, baseUrl: connection.baseUrl);
  @override
  PlaybackState get playbackState => currentPlayback;
  @override
  List<Track> get tracks => empty ? [] : albumTracks;
  @override
  List<Track> get offlineTracks => empty ? [] : albumTracks.reversed.toList();
  @override
  bool get tracksLoading => loading;
  @override
  Future<void> loadTracks(String albumId) async {}

  @override
  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) {
    calls.add('shuffle:${scope?.name}:${mode.name}');
    currentPlayback = currentPlayback.copyWith(
      shuffleMode: mode,
      shuffleScope: scope,
    );
  }

  @override
  Future<void> queueAlbum(String albumId, {String? startTrackId}) async {
    expect(currentPlayback.shuffleMode, ShuffleMode.off);
    calls.add('server:$albumId:$startTrackId');
  }

  @override
  Future<void> playOfflineTrack(
    String trackId, {
    List<Track>? tracks,
    bool localLikedQueue = false,
  }) async {
    expect(currentPlayback.shuffleMode, ShuffleMode.off);
    calls.add('local:$trackId:${tracks?.map((track) => track.id).join(',')}');
  }
}

class _AlbumConnection extends ServerConnection {
  _AlbumConnection() : super(baseUrl: 'http://server.test/api/v1');

  @override
  String buildAlbumCoverUrl(String albumId) => '';
}

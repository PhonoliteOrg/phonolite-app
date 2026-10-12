import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/library_page.dart';
import 'package:phonolite_app/pages/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/local_artist_detail_screen.dart';
import 'package:phonolite_app/widgets/display/search_result_tile.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final connected in [false, true]) {
    testWidgets(
      'search shows local types and counts while connected=$connected',
      (tester) async {
        final controller = _Controller(connected: connected);
        try {
          await _pumpSearch(tester, controller, 'Alice');
          expect(find.text('Local Library Results'), findsOneWidget);
          expect(find.text('3 local matches'), findsOneWidget);
          final localTiles = tester.widgetList<SearchResultTile>(
            find.byType(SearchResultTile),
          );
          expect(localTiles.map((tile) => tile.result.kind), [
            'artist',
            'album',
            'track',
          ]);
          expect(localTiles.every((tile) => tile.useLocalArtwork), isTrue);
          expect(
            find.text('Server Library Results'),
            connected ? findsOneWidget : findsNothing,
          );
          if (connected) expect(find.text('0 server matches'), findsOneWidget);
          expect(find.text('Connected Server Results'), findsNothing);
          expect(tester.takeException(), isNull);

          await tester.enterText(find.byType(TextField), 'no matching song');
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('0 local matches'), findsOneWidget);
          expect(find.text('No local results'), findsOneWidget);
          expect(find.byType(SearchResultTile), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
        }
      },
    );
  }

  for (final kind in ['artist', 'album', 'track']) {
    testWidgets(
      'local $kind search selection uses downloaded detail and playback',
      (tester) async {
        final controller = _Controller(connected: true);
        try {
          await _pumpSearch(tester, controller, 'Alice');
          final tile = find.byWidgetPredicate(
            (widget) =>
                widget is SearchResultTile && widget.result.kind == kind,
          );
          await tester.tap(tile);
          await tester.pumpAndSettle();
          if (kind == 'artist') {
            expect(find.byType(LocalArtistDetailScreen), findsOneWidget);
          } else {
            expect(find.byType(LocalAlbumDetailScreen), findsOneWidget);
          }
          expect(controller.played, kind == 'track' ? ['track'] : isEmpty);
          if (kind == 'track') expect(controller.playedQueue, ['track']);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await controller.close();
        }
      },
    );
  }
}

Future<void> _pumpSearch(
  WidgetTester tester,
  _Controller controller,
  String query,
) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    AppScope(controller: controller, child: wrapInTestApp(const LibraryPage())),
  );
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 500));
}

class _Controller extends AppController {
  _Controller({required this.connected})
    : super(connection: ServerConnection(baseUrl: 'http://server.test/api/v1'));

  final bool connected;
  final played = <String>[];
  List<String> playedQueue = [];
  static final _track = Track(
    id: 'track',
    title: 'Morning',
    artist: 'Alice',
    artistId: 'artist',
    album: 'First Light',
    albumId: 'album',
    durationMs: 60000,
    liked: false,
    inPlaylists: false,
  );

  @override
  AuthState get authState =>
      AuthState(isAuthorized: connected, baseUrl: connection.baseUrl);

  @override
  List<Artist> get artists => [
    Artist(id: 'artist', name: 'Alice', albumCount: 1),
  ];

  @override
  bool get hasMoreArtists => false;

  @override
  List<Track> get offlineTracks => [_track];

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => OfflineLibrarySnapshot(
    tracks: offlineTracks,
    artistGroups: offlineArtistGroups(offlineTracks),
    liked: [],
    playlists: [],
    playlistTracks: [],
    revision: 1,
  );

  @override
  Future<void> search(String query, {String? filter}) async {}

  @override
  Future<void> playOfflineTrack(
    String trackId, {
    List<Track>? tracks,
    bool localLikedQueue = false,
  }) async {
    played.add(trackId);
    playedQueue = tracks?.map((track) => track.id).toList() ?? [];
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:phonolite_app/widgets/inputs/search_hud.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/modals/add_to_playlist_modal.dart';
import 'package:phonolite_app/widgets/modals/obsidian_dialog.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final isLocal in [true, false]) {
    testWidgets(
      '${isLocal ? 'local' : 'server'} mobile track search has the shared actions modal',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = (await tester.runAsync(
          () async => _Controller(connected: !isLocal),
        ))!;
        var openedTrack = 0;
        try {
          await tester.pumpWidget(
            AppScope(
              controller: controller,
              child: wrapInTestApp(
                SearchResultTile(
                  result: SearchResult(
                    kind: 'track',
                    id: 'track',
                    title: 'Morning',
                    albumId: 'album',
                  ),
                  connection: controller.connection,
                  useLocalArtwork: isLocal,
                  onTap: () => openedTrack++,
                ),
              ),
            ),
          );
          final connection = controller.connection as _SearchConnection;
          expect(connection.trackFetches, 0);
          for (final action in [
            'Like',
            if (!isLocal) 'Download',
            'Add to playlist',
          ]) {
            await tester.tap(find.byTooltip('Track actions'));
            await tester.pumpAndSettle();
            expect(find.byType(ObsidianAlertDialog), findsOneWidget);
            expect(find.byType(PopupMenuItem<int>), findsNothing);
            expect(find.text('Like'), findsOneWidget);
            expect(
              find.text('Download'),
              isLocal ? findsNothing : findsOneWidget,
            );
            await tester.tap(find.text(action));
            await tester.pumpAndSettle();
          }
          expect(controller.actions, [
            isLocal ? 'like:local' : 'like:server',
            if (!isLocal) 'download',
          ]);
          expect(find.byType(AddToPlaylistModal), findsOneWidget);
          expect(
            find.text('Add to ${isLocal ? 'local' : 'server'} playlist'),
            findsOneWidget,
          );
          expect(connection.trackFetches, isLocal ? 0 : 3);
          expect(openedTrack, 0);
          if (!isLocal) {
            await tester.tap(find.text('CLOSE'));
            await tester.pumpAndSettle();
            connection.failTrackFetch = true;
            await tester.tap(find.byTooltip('Track actions'));
            await tester.pumpAndSettle();
            expect(find.text('Unable to load track actions.'), findsOneWidget);
            await tester.tap(find.text('CLOSE'));
            await tester.pumpAndSettle();
            expect(find.byType(ObsidianAlertDialog), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(controller.close);
        }
      },
    );
  }

  for (final connected in [false, true]) {
    testWidgets(
      'dragging a short search dismisses focus for connected=$connected',
      (tester) async {
        final controller = _Controller(connected: connected);
        try {
          await _pumpSearch(tester, controller, 'no matching song');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.focusNode!.hasFocus, isTrue);
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final gesture = await tester.startGesture(
            Offset(viewport.center.dx, viewport.bottom - 100),
          );
          await gesture.moveBy(const Offset(0, -32));
          await tester.pump();
          await gesture.moveBy(const Offset(0, -128));
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(field.focusNode!.hasFocus, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(field.controller!.text, 'no matching song');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  for (final connected in [false, true]) {
    testWidgets(
      'scrolling dismisses library search selection for connected=$connected',
      (tester) async {
        final controller = _Controller(connected: connected, trackCount: 20);
        try {
          await _pumpSearch(tester, controller, 'Alice');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final field = tester.widget<TextField>(find.byType(TextField));
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          editable.selectAll(SelectionChangedCause.toolbar);
          await tester.pump();
          editable.showToolbar();
          await tester.pumpAndSettle();
          expect(field.focusNode!.hasFocus, isTrue);
          expect(field.controller!.selection.isCollapsed, isFalse);
          expect(editable.selectionOverlay, isNotNull);
          final position = Scrollable.of(
            tester.element(find.byType(SearchHud)),
          ).position;
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final gesture = await tester.startGesture(
            Offset(viewport.center.dx, viewport.bottom - 100),
          );
          await gesture.moveBy(const Offset(0, -32));
          await tester.pump();
          await gesture.moveBy(const Offset(0, -128));
          await tester.pump();
          await tester.pump();

          expect(position.pixels, greaterThan(0));
          expect(field.focusNode!.hasFocus, isFalse);
          expect(editable.selectionOverlay, isNull);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(field.controller!.text, 'Alice');
          await gesture.up();
          await tester.pumpAndSettle();

          // Returning to search still allows normal editing of the query.
          position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
          expect(field.focusNode!.hasFocus, isTrue);
          await tester.enterText(find.byType(TextField), 'Alice Morning');
          await tester.pump(const Duration(milliseconds: 500));
          expect(field.controller!.text, 'Alice Morning');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'desktop wheel scrolling retains search focus for connected=$connected',
      (tester) async {
        final controller = _Controller(connected: connected, trackCount: 20);
        try {
          await _pumpSearch(tester, controller, 'Alice');
          final field = tester.widget<TextField>(find.byType(TextField));
          field.controller!.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 5,
          );
          await tester.pump();
          final position = Scrollable.of(
            tester.element(find.byType(SearchHud)),
          ).position;
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final pointer = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(
            pointer.hover(Offset(viewport.center.dx, viewport.bottom - 100)),
          );
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, 160)));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(0));
          expect(field.focusNode!.hasFocus, isTrue);
          expect(field.controller!.selection.isCollapsed, isFalse);
          expect(field.controller!.text, 'Alice');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'cursor changes do not rebuild the library for connected=$connected',
      (tester) async {
        final controller = _Controller(connected: connected);
        try {
          await _pumpSearch(tester, controller, 'Alice');
          final text = tester
              .widget<TextField>(find.byType(TextField))
              .controller!;
          final readsBeforeSelection = controller.librarySnapshotReads;
          text.selection = const TextSelection.collapsed(offset: 0);
          await tester.pump();
          expect(
            controller.librarySnapshotReads,
            readsBeforeSelection,
            reason:
                'Focusing or moving the cursor must not rebuild/filter the full music library',
          );
          text.value = text.value.copyWith(
            composing: const TextRange(start: 0, end: 1),
          );
          await tester.pump();
          expect(controller.librarySnapshotReads, readsBeforeSelection);
          expect(find.byType(SearchResultTile), findsNWidgets(3));

          await tester.enterText(find.byType(TextField), 'no matching song');
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            controller.librarySnapshotReads,
            greaterThan(readsBeforeSelection),
          );
          expect(find.byType(SearchResultTile), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
        }
      },
    );
  }

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
  _Controller({required this.connected, this.trackCount = 1})
    : super(connection: _SearchConnection());

  final bool connected;
  final int trackCount;
  int librarySnapshotReads = 0;
  final played = <String>[];
  final actions = <String>[];
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
  List<Track> get offlineTracks => [
    _track,
    for (var index = 1; index < trackCount; index++)
      _track.copyWith(id: 'track-$index'),
  ];

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot {
    librarySnapshotReads++;
    return OfflineLibrarySnapshot(
      tracks: offlineTracks,
      artistGroups: offlineArtistGroups(offlineTracks),
      liked: [],
      playlists: [],
      playlistTracks: [],
      revision: 1,
    );
  }

  @override
  Future<void> search(String query, {String? filter}) async {}

  @override
  Future<void> toggleLike(Track track) async => actions.add('like:server');
  @override
  Future<void> toggleLocalLike(Track track) async => actions.add('like:local');
  @override
  Future<void> downloadTrack(Track track) async => actions.add('download');
  @override
  Future<void> loadLocalPlaylists() async {}
  @override
  Future<void> loadPlaylists() async {}

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

class _SearchConnection extends ServerConnection {
  _SearchConnection() : super(baseUrl: 'http://server.test/api/v1');

  int trackFetches = 0;
  bool failTrackFetch = false;

  @override
  String buildAlbumCoverUrl(String albumId) => '';

  @override
  Future<Track> fetchTrackById(String trackId) async {
    trackFetches++;
    if (failTrackFetch) throw StateError('Track unavailable');
    return _Controller._track;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/ui/app_scope.dart';

import '../support/page_test_controller.dart';
import '../support/widget_test_helpers.dart';

final _albumOne = [downloadedPageTrack('a1', title: 'First Song'), downloadedPageTrack('a2', title: 'Second Song')];
final _albumTwo = [downloadedPageTrack('b1', album: 'Album 2', title: 'Other Song')];

typedef _RemovalCase = ({
  String page,
  void Function(PageTestController app) seed,
  Widget Function(PageTestController app, DisplaySettingsController display) build,
  String editTooltip,
  String select,
  String target,
  List<String> removedIds,
  String label,
  OfflineDeletionScopeKind scope,
  String? scopeId,
});

final List<_RemovalCase> _cases = [
  (
    page: 'Local artist',
    seed: (app) => app.downloadedTracks = [..._albumOne, ..._albumTwo],
    build: (app, _) => LocalArtistDetailScreen(group: offlineArtistGroups(app.downloadedTracks).single),
    editTooltip: 'Edit',
    select: 'Album 1',
    target: '2 downloads for Album 1',
    removedIds: ['a1', 'a2'],
    label: 'Album 1',
    scope: OfflineDeletionScopeKind.album,
    scopeId: 'album-album-1',
  ),
  (
    page: 'Local album',
    seed: (app) => app.downloadedTracks = _albumOne,
    build: (app, _) => LocalAlbumDetailScreen(album: offlineArtistGroups(app.downloadedTracks).single.albums.single),
    editTooltip: 'Edit',
    select: 'First Song',
    target: '"Album 1"',
    removedIds: ['a1'],
    label: 'Album 1',
    scope: OfflineDeletionScopeKind.track,
    scopeId: null,
  ),
  (
    page: 'Playlist detail',
    seed: (app) => app
      ..connected = true
      ..serverPlaylistList = [
        Playlist(id: 'playlist-1', name: 'Mix', trackIds: const ['a1', 'a2']),
      ]
      ..serverPlaylistTracks = _albumOne,
    build: (_, _) => const PlaylistDetailView(playlistId: 'playlist-1'),
    editTooltip: 'Edit tracks',
    select: 'Second Song',
    target: '"Mix"',
    removedIds: ['a2'],
    label: 'Mix',
    scope: OfflineDeletionScopeKind.track,
    scopeId: null,
  ),
  (
    page: 'Liked',
    seed: (app) => app
      ..connected = true
      ..localLikedTracks = _albumOne
      ..serverLikedTracks = _albumTwo,
    build: (_, display) => LikedPage(displaySettings: display),
    editTooltip: 'Edit tracks',
    select: 'First Song',
    target: '"liked tracks"',
    removedIds: ['a1'],
    label: 'liked tracks',
    scope: OfflineDeletionScopeKind.track,
    scopeId: null,
  ),
];

void main() {
  for (final entry in _cases) {
    testWidgets('${entry.page} removes selected downloads only after the Remove download confirmation', (tester) async {
      final app = PageTestController();
      entry.seed(app);
      final display = await memoryDisplaySettings();
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(AppScope(controller: app, child: wrapInTestApp(entry.build(app, display))));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(entry.editTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove selected'));
      await tester.pumpAndSettle();
      expect(find.text('Remove download'), findsNothing, reason: 'Nothing is selected yet.');

      await tester.tap(find.text(entry.select));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove selected'));
      await tester.pumpAndSettle();

      expect(find.text('Remove download'), findsOneWidget);
      expect(find.textContaining('Remove ${entry.target} from this device?'), findsOneWidget);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('Remove download'), findsNothing);
      expect(app.removals, isEmpty);

      await tester.tap(find.byTooltip('Remove selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REMOVE'));
      await tester.pumpAndSettle();

      final removal = app.removals.single;
      expect(removal.trackIds, entry.removedIds);
      expect(removal.label, entry.label);
      expect(removal.scope.kind, entry.scope);
      expect(removal.scope.id, entry.scopeId);
      expect(find.byTooltip('Remove selected'), findsNothing, reason: 'Removal ends the selection.');
      expect(find.byTooltip(entry.editTooltip), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      display.dispose();
      await app.close();
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/pages/library/artist_detail_screen.dart';
import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';

import '../support/page_test_controller.dart';
import '../support/widget_test_helpers.dart';

typedef _EmptyCase = ({
  String name,
  bool connected,
  Widget Function(DisplaySettingsController display) page,
  Future<void> Function(WidgetTester tester)? act,
  List<String> visible,
});

final _album = Album(id: 'album-1', title: 'Album 1', artist: 'Artist A', artistId: 'artist-a', trackCount: 0);
const _localArtist = OfflineArtistGroup(id: 'artist-a', name: 'Artist A', albums: []);
const _localAlbum = OfflineAlbumGroup(
  id: 'album-1',
  title: 'Album 1',
  artist: 'Artist A',
  artistId: 'artist-a',
  tracks: [],
);

final List<_EmptyCase> _cases = [
  (
    name: 'signed-out Library without downloads',
    connected: false,
    page: (display) => LibraryPage(displaySettings: display),
    act: null,
    visible: ['No downloaded tracks', 'Connect to a server and download tracks to listen offline.'],
  ),
  (
    name: 'connected Library without downloads or server artists',
    connected: true,
    page: (display) => LibraryPage(displaySettings: display),
    act: null,
    visible: [
      'No downloaded tracks',
      'Download tracks from a connected server to keep them here.',
      'No server artists',
      'This connected server has no artists yet.',
    ],
  ),
  (
    name: 'connected Library search without server hits',
    connected: true,
    page: (display) => LibraryPage(displaySettings: display),
    act: (tester) async {
      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    },
    visible: ['No server results', 'No local results'],
  ),
  (
    name: 'server artist without albums',
    connected: true,
    page: (_) => ArtistDetailScreen(
      artist: Artist(id: 'artist-a', name: 'Artist A', albumCount: 0),
    ),
    act: null,
    visible: ['Artist has no albums'],
  ),
  (
    name: 'server album without tracks',
    connected: true,
    page: (_) => AlbumDetailScreen(album: _album, artistName: _album.artist),
    act: null,
    visible: ['No tracks', 'Pick another album to see tracks.'],
  ),
  (
    name: 'local artist without downloaded albums',
    connected: false,
    page: (_) => const LocalArtistDetailScreen(group: _localArtist),
    act: null,
    visible: ['Artist has no downloaded albums'],
  ),
  (
    name: 'local album without downloaded tracks',
    connected: false,
    page: (_) => const LocalAlbumDetailScreen(album: _localAlbum),
    act: null,
    visible: ['No downloaded tracks', 'Downloaded tracks for this album appear here.'],
  ),
  (
    name: 'signed-out Playlists without playlists',
    connected: false,
    page: (display) => PlaylistsPage(displaySettings: display),
    act: null,
    visible: ['No playlists'],
  ),
  (
    name: 'connected Playlists without playlists',
    connected: true,
    page: (display) => PlaylistsPage(displaySettings: display),
    act: null,
    visible: ['No local playlists', 'No server playlists'],
  ),
  (
    name: 'loaded playlist without tracks',
    connected: true,
    page: (_) => const PlaylistDetailView(playlistId: 'playlist-1'),
    act: null,
    visible: ['No tracks yet.'],
  ),
  (
    name: 'signed-out Liked without liked tracks',
    connected: false,
    page: (display) => LikedPage(displaySettings: display),
    act: null,
    visible: ['No liked tracks'],
  ),
  (
    name: 'connected Liked without liked tracks',
    connected: true,
    page: (display) => LikedPage(displaySettings: display),
    act: null,
    visible: ['No local liked tracks', 'No server liked tracks'],
  ),
];

void main() {
  for (final entry in _cases) {
    testWidgets('${entry.name} shows its empty state', (tester) async {
      final app = PageTestController(connected: entry.connected);
      final display = await memoryDisplaySettings();
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(AppScope(controller: app, child: wrapInTestApp(entry.page(display))));
      await tester.pumpAndSettle();
      await entry.act?.call(tester);

      for (final text in entry.visible) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      display.dispose();
      await app.close();
    });
  }
}

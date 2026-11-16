import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';

import '../support/app_driver.dart';
import '../support/feature_scenario.dart';
import '../support/feature_world.dart';
import '../support/library_steps.dart';
import '../support/platform_profile.dart';

/// Offline library behavior expected on every platform: browsing downloaded
/// artists and albums, search, layout preference, playback and navigation.
final libraryScenarios = [
  FeatureScenario(
    id: 'library.downloaded_artists',
    description: 'The Library tab lists every downloaded artist',
    covers: ['navigation.library'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      app.expectPage<PlaylistsPage>();

      await app.openTab('Library');
      app.expectPage<LibraryPage>();
      app.expectVisible('Alice');
      app.expectVisible('Bruno');
    },
  ),
  FeatureScenario(
    id: 'library.artist_album_drilldown',
    description: 'Artist opens its albums, album lists its tracks, Back links return in order',
    covers: ['library.artist_open', 'artist.album_open', 'album.back', 'artist.back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openDemoAlbum(app);
      app.expectVisible('First Light');
      app.expectVisible('Third Coast');
      app.expectNotVisible('Northern Lines');

      await app.tapBackLink('Back to artist');
      app.expectPage<LocalArtistDetailScreen>();

      await app.tapBackLink('Back to library');
      app.expectPage<LibraryPage>();
    },
  ),
  FeatureScenario(
    id: 'library.platform_back',
    description: "The platform's own back mechanism returns one screen at a time",
    covers: ['navigation.system_back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openDemoAlbum(app);

      await app.goBack();
      app.expectPage<LocalArtistDetailScreen>();

      await app.goBack();
      app.expectPage<LibraryPage>();
    },
  ),
  FeatureScenario(
    id: 'library.mouse_history',
    description: 'Mouse Forward reopens the screen Back just left',
    covers: ['desktop.mouse_history'],
    requires: {Capability.mouseForward},
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openArtist('Alice');

      await app.goBack();
      app.expectPage<LibraryPage>();

      await app.goForward();
      app.expectPage<LocalArtistDetailScreen>();
    },
  ),
  FeatureScenario(
    id: 'library.tab_history',
    description: 'Switching tabs away and back keeps the open artist',
    covers: ['navigation.tab_history', 'navigation.playlists'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openArtist('Alice');

      await app.openTab('Playlists');
      app.expectPage<PlaylistsPage>();

      await app.openTab('Library');
      app.expectPage<LocalArtistDetailScreen>();
    },
  ),
  FeatureScenario(
    id: 'library.search',
    description: 'Typing filters downloaded music; clearing restores the catalog',
    covers: ['library.search_focus', 'library.search_type', 'library.search_clear'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.search('river');
      app.expectVisible('River Song');
      app.expectNotVisible('First Light');

      await app.clearSearch();
      expect(app.searchText, isEmpty);
      app.expectVisible('Alice');
      app.expectNotVisible('River Song');
    },
  ),
  FeatureScenario(
    id: 'library.search_plays_track',
    description: 'Choosing a track search result plays it',
    covers: ['library.result_track'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.search('northern');
      await app.openSearchResult('Northern Lines');

      expect(app.currentTrack?.title, 'Northern Lines');
      expect(app.playback.isPlaying, isTrue);
    },
  ),
  FeatureScenario(
    id: 'library.collection_view',
    description: 'The layout toggle switches artists between cards and rows',
    covers: ['library.collection_view'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      final startedAsList = app.collectionShowsList;

      await app.toggleCollectionView();
      expect(app.collectionShowsList, !startedAsList);
      expect(find.byType(startedAsList ? ArtistCard : ArtistRowTile), findsWidgets);

      await app.toggleCollectionView();
      expect(app.collectionShowsList, startedAsList);
      expect(find.byType(startedAsList ? ArtistRowTile : ArtistCard), findsWidgets);
    },
  ),
  FeatureScenario(
    id: 'library.play_album',
    description: 'Play album starts the first track with only that album queued',
    covers: ['album.play'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openDemoAlbum(app);
      await app.playAlbum();

      expect(app.currentTrack?.title, 'First Light');
      expect(app.playback.isPlaying, isTrue);
    },
  ),
  FeatureScenario(
    id: 'library.play_track',
    description: 'Tapping an album track plays that track',
    covers: ['track.play'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openDemoAlbum(app);
      await app.playTrack('Third Coast');

      expect(app.currentTrack?.title, 'Third Coast');
      expect(app.playback.isPlaying, isTrue);
    },
  ),
];

Future<void> _openDemoAlbum(AppDriver app) async {
  await app.openArtist('Alice');
  app.expectPage<LocalArtistDetailScreen>();
  app.expectVisible('Late Album');

  await app.openAlbum('Demo Album');
  app.expectPage<LocalAlbumDetailScreen>();
}

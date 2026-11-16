import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';

import '../support/app_driver.dart';
import '../support/feature_scenario.dart';
import '../support/feature_world.dart';
import '../support/library_steps.dart';
import '../support/player_steps.dart';
import '../support/playlist_steps.dart';

/// Local playlist behavior expected on every platform: browsing, creating,
/// renaming, playing and deleting playlists.
final playlistScenarios = [
  FeatureScenario(
    id: 'playlists.open_and_back',
    description: 'A playlist opens to its tracks in order and Back returns to the collection',
    covers: ['playlists.open', 'playlist.back'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openRoadTrip(app);
      app.expectVisible('River Song');
      app.expectVisible('First Light');
      app.expectNotVisible('Northern Lines');

      await app.tapBackLink('Back to playlists');
      app.expectPage<PlaylistsPage>();
      app.expectVisible('Quiet Hours');
    },
  ),
  FeatureScenario(
    id: 'playlists.create',
    description: 'Saving the editor creates a local playlist that appears in the collection',
    covers: ['playlists.create_open', 'playlist_editor.name', 'playlist_editor.description', 'playlist_editor.save'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      await app.openCreatePlaylist();
      await app.fillPlaylistEditor(name: 'Gym Mix', description: 'Fast songs');
      await app.savePlaylistEditor();

      expect(app.localPlaylistNames, contains('Gym Mix'));
      expect(app.controller.localPlaylists.last.description, 'Fast songs');
      app.expectVisible('Gym Mix');
    },
  ),
  FeatureScenario(
    id: 'playlists.create_discard',
    description: 'Dismissing the editor discards the draft',
    covers: ['playlists.create_open', 'playlist_editor.close'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      await app.openCreatePlaylist();
      await app.fillPlaylistEditor(name: 'Never Saved');
      await app.dismissDialog();

      expect(app.isEditorOpen, isFalse);
      expect(app.localPlaylistNames, isNot(contains('Never Saved')));
      app.expectNotVisible('Never Saved');
    },
  ),
  FeatureScenario(
    id: 'playlist.rename',
    description: 'Edit details renames the open playlist',
    covers: ['playlist.edit_details', 'playlist_editor.name', 'playlist_editor.save'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openRoadTrip(app);
      await app.openPlaylistDetails();
      await app.fillPlaylistEditor(name: 'Long Drive');
      await app.savePlaylistEditor();

      expect(app.localPlaylistNames, ['Long Drive', 'Quiet Hours']);
      app.expectVisible('Long Drive');
    },
  ),
  FeatureScenario(
    id: 'playlist.play',
    description: 'Play playlist starts the first track and queues the playlist in order',
    covers: ['playlist.play'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openRoadTrip(app);
      await app.playPlaylist();
      expect(app.currentTrack?.title, 'River Song');
      expect(app.playback.isPlaying, isTrue);

      await app.next();
      expect(app.currentTrack?.title, 'First Light');
    },
  ),
  FeatureScenario(
    id: 'playlist.play_track',
    description: 'Tapping a playlist track plays it within the playlist queue',
    covers: ['track.play'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await _openRoadTrip(app);
      await app.playTrack('First Light');

      expect(app.currentTrack?.title, 'First Light');
      expect(app.playback.isPlaying, isTrue);
    },
  ),
  FeatureScenario(
    id: 'playlists.hold_to_play',
    description: 'Holding a playlist tile starts it from the top without opening it',
    covers: ['playlists.long_press'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      await app.holdPlaylist('Quiet Hours');

      expect(app.currentTrack?.title, 'Northern Lines');
      expect(app.playback.isPlaying, isTrue);
      app.expectPage<PlaylistsPage>();
    },
  ),
  FeatureScenario(
    id: 'playlists.delete',
    description: 'Selecting a playlist and confirming removal deletes only that playlist',
    covers: ['playlists.edit', 'playlists.select', 'playlists.delete_open', 'playlists.delete_confirm'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      await app.editPlaylists();
      await app.togglePlaylistSelection('Quiet Hours');
      await app.removeSelectedPlaylists();
      app.expectVisible('Are you sure you want to delete this playlist?');

      await app.modalAction('Yes');
      expect(app.localPlaylistNames, ['Road Trip']);
      app.expectNotVisible('Quiet Hours');
    },
  ),
  FeatureScenario(
    id: 'playlists.delete_cancel',
    description: 'Cancelling the confirmation and the selection keeps every playlist',
    covers: ['playlists.delete_cancel', 'playlists.cancel_selection'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      await app.openTab('Playlists');
      await app.editPlaylists();
      await app.togglePlaylistSelection('Quiet Hours');
      await app.removeSelectedPlaylists();
      await app.modalAction('Cancel');

      await app.cancelPlaylistSelection();
      expect(app.localPlaylistNames, ['Road Trip', 'Quiet Hours']);
      app.expectVisible('Quiet Hours');
    },
  ),
  FeatureScenario(
    id: 'playlists.shared_collection_view',
    description: 'The playlist layout toggle also changes the Library layout',
    covers: ['playlists.collection_view'],
    world: () => FeatureWorld.offlineLibrary,
    run: (app) async {
      final startedAsList = app.collectionShowsList;

      await app.openTab('Playlists');
      await app.toggleCollectionView(page: 'Playlist');
      expect(app.collectionShowsList, !startedAsList);

      await app.openTab('Library');
      expect(find.byType(startedAsList ? ArtistCard : ArtistRowTile), findsWidgets);
    },
  ),
];

Future<void> _openRoadTrip(AppDriver app) async {
  await app.openTab('Playlists');
  await app.openPlaylist('Road Trip');
  app.expectPage<PlaylistDetailView>();
}

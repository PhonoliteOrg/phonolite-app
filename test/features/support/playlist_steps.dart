import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';

import 'app_driver.dart';

/// Playlist collection, detail and editor steps.
extension PlaylistSteps on AppDriver {
  Finder get _editorFields => find.descendant(of: find.byType(PlaylistEditorModal), matching: find.byType(TextField));

  bool get isEditorOpen => find.byType(PlaylistEditorModal).evaluate().isNotEmpty;

  List<String> get localPlaylistNames => [for (final playlist in controller.localPlaylists) playlist.name];

  Finder _playlistTile(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byWidgetPredicate((widget) => widget is AlbumCard || widget is AlbumRowTile),
  );

  Future<void> openPlaylist(String name) =>
      activate(find.descendant(of: _playlistTile(name), matching: find.text(name)));

  /// Starts a playlist from its collection tile without opening it.
  Future<void> holdPlaylist(String name) => hold(_playlistTile(name));

  Future<void> openCreatePlaylist() async {
    await activate(labelled('Create playlist'));
    expect(isEditorOpen, isTrue, reason: 'Create playlist should open the editor');
  }

  Future<void> openPlaylistDetails() async {
    await activate(labelled('Edit details'));
    expect(isEditorOpen, isTrue, reason: 'Edit details should open the editor');
  }

  Future<void> fillPlaylistEditor({String? name, String? description}) async {
    if (name != null) {
      await tester.enterText(_editorFields.at(0), name);
    }

    if (description != null) {
      await tester.enterText(_editorFields.at(1), description);
    }

    await settle();
  }

  Future<void> savePlaylistEditor() async {
    await modalAction('Save');
    expect(isEditorOpen, isFalse, reason: 'a valid draft should save and close the editor');
  }

  Future<void> playPlaylist() => activate(labelled('Play playlist'));

  // Selection mode on the collection.

  Future<void> editPlaylists() => activate(labelled('Edit playlists'));

  Future<void> togglePlaylistSelection(String name) => activate(_playlistTile(name));

  Future<void> removeSelectedPlaylists() => activate(labelled('Remove selected'));

  Future<void> cancelPlaylistSelection() => activate(labelled('Cancel'));
}

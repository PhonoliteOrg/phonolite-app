import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

final likedJourneys = [
  UiJourney(
    id: 'liked.scroll',
    feature: 'liked',
    description: 'Scroll local/server liked tracks without changing likes',
    interactions: ['liked.scroll'],
    run: (ui) async {
      await ui.tab('Liked');
      await ui.scrollRoundTrip();
    },
  ),
  UiJourney(
    id: 'liked.create_playlist',
    feature: 'liked',
    description:
        'Create a playlist from each liked source, verify its tracks and order, '
        'then delete only that test playlist',
    interactions: ['liked.create_playlist', 'playlist_editor.name', 'playlist_editor.save'],
    run: (ui) async {
      await ui.tab('Liked');
      final app = ui.controller;
      final local = List<Track>.of(app.localLiked);
      final server = app.authState.isAuthorized ? List<Track>.of(app.liked) : <Track>[];
      if (local.isEmpty && server.isEmpty) {
        throw const MissingPrerequisite('No liked tracks');
      }

      for (final isLocal in [if (local.isNotEmpty) true, if (server.isNotEmpty) false]) {
        await _createAndVerify(
          ui,
          isLocal: isLocal,
          expected: isLocal ? local : server,
          chooseTarget: local.isNotEmpty && server.isNotEmpty,
        );
      }
    },
  ),
];

String _key(Track track) => '${track.title}\u0000${track.artist}';

Future<void> _createAndVerify(
  UiHarness ui, {
  required bool isLocal,
  required List<Track> expected,
  required bool chooseTarget,
}) async {
  final app = ui.controller;
  final name =
      'UI liked ${isLocal ? 'local' : 'server'} '
      '${DateTime.now().millisecondsSinceEpoch % 100000}';

  await ui.tooltip('Create playlist from liked tracks');
  final editor = find.byType(PlaylistEditorModal);
  expect(editor, findsOneWidget);
  expect(ui.tester.widget<PlaylistEditorModal>(editor).title, 'Create playlist from liked tracks');
  if (chooseTarget) {
    await ui.tap(find.descendant(of: editor, matching: find.text(isLocal ? 'LOCAL' : 'SERVER')));
  }
  final fields = find.descendant(of: editor, matching: find.byType(TextField));
  await ui.tester.enterText(fields.at(0), name);
  FocusManager.instance.primaryFocus?.unfocus();
  await ui.animate();
  await ui.tap(find.descendant(of: editor, matching: find.text('SAVE')));
  await ui.waitUntil(
    () => !hasMatches(editor),
    description: 'editor to close after saving',
    timeout: const Duration(seconds: 60),
  );

  List<Playlist> playlists() => isLocal ? app.localPlaylists : app.playlists;
  Playlist? created() => playlists().where((playlist) => playlist.name == name).firstOrNull;
  await ui.waitUntil(() => created() != null, description: 'playlist $name');
  final playlist = created()!;

  try {
    if (isLocal) {
      await app.loadLocalPlaylistTracks(playlist.id);
      await ui.waitUntil(
        () => app.localPlaylistTracks.length == expected.length,
        description: '${expected.length} tracks in $name',
        timeout: const Duration(seconds: 30),
      );
      expect(app.localPlaylistTracks.map(_key).toList(), expected.map(_key).toList());
    } else {
      await ui.waitUntil(
        () => created()?.trackIds.length == expected.length,
        description: '${expected.length} tracks in $name',
        timeout: const Duration(seconds: 30),
      );
      expect(created()!.trackIds, expected.map((track) => track.id).toList());
    }
    debugPrint('liked.create_playlist: $name has ${expected.length} tracks in order');
  } finally {
    if (isLocal) {
      await app.deleteLocalPlaylist(playlist.id);
    } else {
      await app.deletePlaylist(playlist.id);
    }
    await ui.animate();
  }
}

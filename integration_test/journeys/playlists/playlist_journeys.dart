import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/modals/playlist_editor_modal.dart';
import 'package:phonolite_app/widgets/display/album_card.dart';
import 'package:phonolite_app/widgets/display/album_row_tile.dart';
import 'package:phonolite_app/pages/playlist_detail_view.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

final playlistJourneys = [
  UiJourney(
    id: 'playlists.detail_navigation',
    feature: 'playlists',
    description:
        'Open existing playlist, inspect editor, and return without saving',
    interactions: [
      'playlists.open',
      'playlist.edit_details',
      'playlist_editor.close',
      'playlist.back',
    ],
    run: (ui) async {
      await ui.tab('Playlists');
      final cards = find.byWidgetPredicate(
        (w) => w is AlbumCard || w is AlbumRowTile,
      );
      if (cards.evaluate().isEmpty) {
        throw const MissingPrerequisite('No existing playlist to open');
      }
      await ui.tap(cards.first);
      await ui.waitFor(find.byType(PlaylistDetailView));
      await ui.tooltip('Edit details');
      expect(find.byType(PlaylistEditorModal), findsOneWidget);
      await ui.closeDialog();
      await ui.back('Back to playlists');
    },
  ),
  UiJourney(
    id: 'playlists.scroll',
    feature: 'playlists',
    description: 'Scroll existing playlists without starting playback',
    interactions: ['playlists.scroll'],
    run: (ui) async {
      await ui.tab('Playlists');
      await ui.scrollRoundTrip();
    },
  ),
  UiJourney(
    id: 'playlists.create_cancel',
    feature: 'playlists',
    description: 'Open the editor, fill both fields, and discard the draft',
    interactions: [
      'playlists.create_open',
      'playlist_editor.name',
      'playlist_editor.description',
      'playlist_editor.close',
    ],
    run: (ui) async {
      await ui.tab('Playlists');
      final localCount = ui.controller.localPlaylists.length;
      final serverCount = ui.controller.playlists.length;
      await ui.tooltip('Create playlist');
      final editor = find.byType(PlaylistEditorModal);
      expect(editor, findsOneWidget);
      final fields = find.descendant(
        of: editor,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      await ui.tester.enterText(fields.at(0), 'UI test draft');
      await ui.tester.enterText(
        fields.at(1),
        'Discarded by the test; never saved.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await ui.animate();
      await ui.closeDialog();
      expect(editor, findsNothing);
      expect(ui.controller.localPlaylists.length, localCount);
      expect(ui.controller.playlists.length, serverCount);
    },
  ),
  UiJourney(
    id: 'playlists.collection_view',
    feature: 'playlists',
    description: 'Toggle playlist layout and restore it',
    interactions: ['playlists.collection_view'],
    run: (ui) async {
      await ui.tab('Playlists');
      final initial = ui.controller.collectionListMode;
      try {
        for (var n = 0; n < UiHarness.repeats; n++) {
          await ui.tap(ui.semanticControl('Playlist collection view'));
          expect(ui.controller.collectionListMode, !initial);
          await ui.tap(ui.semanticControl('Playlist collection view'));
          expect(ui.controller.collectionListMode, initial);
        }
      } finally {
        if (ui.controller.collectionListMode != initial) {
          await ui.tap(ui.semanticControl('Playlist collection view'));
        }
      }
    },
  ),
];

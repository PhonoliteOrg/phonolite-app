import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/display/artist_card.dart';
import 'package:phonolite_app/widgets/display/artist_row_tile.dart';
import 'package:phonolite_app/widgets/inputs/search_hud.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

final libraryJourneys = [
  UiJourney(
    id: 'library.scroll',
    feature: 'library',
    description: 'Repeated Library scroll down/up with the real catalog',
    interactions: ['library.scroll'],
    run: (ui) async {
      await ui.tab('Library');
      await ui.scrollRoundTrip();
    },
  ),
  UiJourney(
    id: 'library.search',
    feature: 'library',
    description: 'Focus search, enter a query, submit, and clear it',
    interactions: [
      'library.search_focus',
      'library.search_type',
      'library.search_submit',
      'library.search_clear',
    ],
    run: (ui) async {
      await ui.tab('Library');
      final input = find.descendant(
        of: find.byType(SearchHud),
        matching: find.byType(TextField),
      );
      await ui.tap(input);
      try {
        await ui.tester.enterText(input, UiHarness.query);
        await ui.animate(600);
        await ui.tester.testTextInput.receiveAction(TextInputAction.search);
        await ui.animate(600);
        expect(
          ui.tester.widget<TextField>(input).controller!.text,
          UiHarness.query,
        );
        await ui.tooltip('Clear search');
        expect(ui.tester.widget<TextField>(input).controller!.text, isEmpty);
      } finally {
        if (input.evaluate().isNotEmpty) await ui.tester.enterText(input, '');
        FocusManager.instance.primaryFocus?.unfocus();
        await ui.animate();
      }
    },
  ),
  UiJourney(
    id: 'library.collection_view',
    feature: 'library',
    description: 'Switch cards/list and restore the original preference',
    interactions: ['library.collection_view'],
    run: (ui) async {
      await ui.tab('Library');
      final initial = ui.controller.collectionListMode;
      try {
        for (var n = 0; n < UiHarness.repeats; n++) {
          await ui.tap(ui.semanticControl('Library collection view'));
          expect(ui.controller.collectionListMode, !initial);
          await ui.tap(ui.semanticControl('Library collection view'));
          expect(ui.controller.collectionListMode, initial);
        }
      } finally {
        if (ui.controller.collectionListMode != initial) {
          await ui.tap(ui.semanticControl('Library collection view'));
        }
      }
      expect(ui.controller.collectionListMode, initial);
    },
  ),
  UiJourney(
    id: 'library.download_manager',
    feature: 'library',
    description: 'Open and close Download Manager without changing jobs',
    interactions: ['downloads.open', 'downloads.close'],
    run: (ui) async {
      await ui.tab('Library');
      for (var n = 0; n < UiHarness.repeats; n++) {
        await ui.tooltip('Download Manager');
        expect(find.text('Download Manager'), findsWidgets);
        await ui.closeDialog();
      }
    },
  ),
  UiJourney(
    id: 'library.artist_navigation',
    feature: 'library',
    description: 'Open a visible local/server artist and return',
    interactions: ['library.artist_open', 'artist.back'],
    run: (ui) async {
      await ui.tab('Library');
      final artists = find.byWidgetPredicate(
        (w) => w is ArtistCard || w is ArtistRowTile,
      );
      // Sliver rows may be below a Local Music header, so materialize them.
      if (artists.evaluate().isEmpty && ui.scrollable.evaluate().isNotEmpty) {
        await ui.tester.drag(ui.scrollable.first, const Offset(0, -300));
        await ui.animate(600);
      }
      if (artists.evaluate().isEmpty) {
        throw const MissingPrerequisite('No local/server artist is loaded');
      }
      for (var n = 0; n < UiHarness.repeats; n++) {
        await ui.tap(artists.first);
        await ui.waitFor(ui.command('Back to library'));
        await ui.back('Back to library');
      }
    },
  ),
];

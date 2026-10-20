import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/pages/library_page.dart';
import 'package:phonolite_app/pages/liked_page.dart';
import 'package:phonolite_app/pages/playlists_page.dart';
import 'package:phonolite_app/pages/settings_page.dart';
import 'package:phonolite_app/pages/stats_page.dart';
import 'package:phonolite_app/widgets/ui/obsidian_widgets.dart';

import '../../support/journey.dart';
import '../../support/ui_harness.dart';

final navigationJourneys = [
  UiJourney(
    id: 'navigation.primary_tabs',
    feature: 'navigation',
    description: 'Visit every always-visible tab and return to Library',
    interactions: [
      'navigation.library',
      'navigation.playlists',
      'navigation.liked',
      'navigation.settings',
    ],
    run: (ui) async {
      for (final entry in <(String, Type)>[
        ('Playlists', PlaylistsPage),
        ('Liked', LikedPage),
        ('Settings', SettingsPage),
        ('Library', LibraryPage),
      ]) {
        await ui.tab(entry.$1);
        expect(find.byType(entry.$2), findsOneWidget);
        expect(ui.tester.takeException(), isNull);
      }
    },
  ),
  UiJourney(
    id: 'navigation.stats_tab',
    feature: 'navigation',
    description: 'Visit Stats when listening statistics are enabled',
    interactions: ['navigation.stats'],
    run: (ui) async {
      if (!ui.controller.statsCollectionEnabled) {
        throw const MissingPrerequisite(
          'Stats is hidden while statistics collection is disabled',
        );
      }
      for (var n = 0; n < UiHarness.repeats; n++) {
        await ui.tab('Stats');
        expect(find.byType(StatsPage), findsOneWidget);
        await ui.tab('Library');
      }
    },
  ),
  UiJourney(
    id: 'navigation.ordered_tab_pairs',
    feature: 'navigation',
    description: 'Exercise every ordered pair of visible primary tabs',
    interactions: ['navigation.tab_pairs'],
    run: (ui) async {
      final tabs = [
        'Library',
        'Playlists',
        'Liked',
        if (ui.controller.statsCollectionEnabled) 'Stats',
        'Settings',
      ];
      for (final from in tabs) {
        for (final to in tabs.where((tab) => tab != from)) {
          await ui.tab(from);
          await ui.tab(to);
          expect(
            ui.tester.widget<ObsidianNavIcon>(ui.nav(to)).isSelected,
            isTrue,
          );
          expect(ui.tester.takeException(), isNull);
        }
      }
      await ui.tab('Library');
    },
  ),
];

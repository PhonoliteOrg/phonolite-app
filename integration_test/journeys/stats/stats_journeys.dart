import 'package:flutter_test/flutter_test.dart';

import '../../support/journey.dart';

final statsJourneys = [
  UiJourney(
    id: 'stats.scroll',
    feature: 'stats',
    description: 'Scroll listening statistics when its tab is enabled',
    interactions: ['stats.scroll'],
    run: (ui) async {
      if (!ui.controller.statsCollectionEnabled) {
        throw const MissingPrerequisite(
          'Stats is disabled in the current settings',
        );
      }
      await ui.tab('Stats');
      await ui.scrollRoundTrip();
    },
  ),
  UiJourney(
    id: 'stats.status',
    feature: 'stats',
    description: 'Open and dismiss listening history status',
    interactions: ['stats.status_open', 'stats.status_close'],
    run: (ui) async {
      if (!ui.controller.statsCollectionEnabled) {
        throw const MissingPrerequisite(
          'Stats is disabled in the current settings',
        );
      }
      await ui.tab('Stats');
      await ui.tooltip('Listening history status');
      expect(find.text('Listening history'), findsOneWidget);
      await ui.closeDialog();
      expect(find.text('Listening history'), findsNothing);
    },
  ),
];

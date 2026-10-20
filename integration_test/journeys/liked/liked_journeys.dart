import '../../support/journey.dart';

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
];

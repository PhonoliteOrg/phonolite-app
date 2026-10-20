import 'library/library_journeys.dart';
import 'library/detail_journeys.dart';
import 'liked/liked_journeys.dart';
import 'navigation/navigation_journeys.dart';
import 'player/player_journeys.dart';
import 'playlists/playlist_journeys.dart';
import 'settings/settings_journeys.dart';
import 'stats/stats_journeys.dart';

final allJourneys = [
  ...navigationJourneys,
  ...libraryJourneys,
  ...detailJourneys,
  ...playlistJourneys,
  ...likedJourneys,
  ...settingsJourneys,
  ...statsJourneys,
  ...playerJourneys,
];

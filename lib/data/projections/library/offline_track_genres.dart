import 'package:phonolite_app/data/models/library/track.dart';

List<String> offlineTrackGenres(Iterable<Track> tracks) {
  final genres = <String>[];
  final seen = <String>{};

  for (final track in tracks) {
    for (final raw in track.genres) {
      final genre = raw.trim();

      if (genre.isEmpty) {
        continue;
      }

      if (seen.add(genre.toLowerCase())) {
        genres.add(genre);
      }
    }
  }

  return List.unmodifiable(genres);
}

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';

String albumTrackCountLabel(Album album) {
  return album.trackCount == 1 ? '1 track' : '${album.trackCount} tracks';
}

String albumDetailLabel(Album album, {int genreLimit = 2}) {
  final details = <String>[];
  final year = album.year;

  if (year != null) {
    details.add(year.toString());
  }

  details.add(albumTrackCountLabel(album));
  details.addAll(displayGenres(album.genres).take(genreLimit));

  return details.join(' / ');
}

String albumMetaLabel(Album album) => albumDetailLabel(album, genreLimit: 3);

String albumGenresLabel(Album album) {
  final genres = displayGenres(album.genres).take(5).toList(growable: false);

  if (genres.isEmpty) {
    return 'UNKNOWN GENRE';
  }

  return genres.join(' / ');
}

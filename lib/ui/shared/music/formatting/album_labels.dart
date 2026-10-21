import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';

String artistAlbumCountLabel(Artist artist) {
  return artist.releaseCount == 1 ? '1 album' : '${artist.releaseCount} albums';
}

String albumTrackCountLabel(Album album) {
  return album.trackCount == 1 ? '1 track' : '${album.trackCount} tracks';
}

String artistDetailLabel(Artist artist, {int genreLimit = 2}) {
  final details = <String>[
    artistAlbumCountLabel(artist),
    if (artist.collabAlbumCount > 0)
      '${artist.collabAlbumCount} collab ${artist.collabAlbumCount == 1 ? 'album' : 'albums'}',
  ];

  details.addAll(displayGenres(artist.genres).take(genreLimit));

  return details.join(' / ');
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

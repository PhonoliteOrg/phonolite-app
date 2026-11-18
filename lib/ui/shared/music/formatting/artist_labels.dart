import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';

String artistAlbumCountLabel(Artist artist) {
  return artist.releaseCount == 1 ? '1 album' : '${artist.releaseCount} albums';
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

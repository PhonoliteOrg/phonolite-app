import '../../entities/models.dart';

String artistAlbumCountLabel(Artist artist) {
  return artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums';
}

String albumTrackCountLabel(Album album) {
  return album.trackCount == 1 ? '1 track' : '${album.trackCount} tracks';
}

String artistDetailLabel(Artist artist, {int genreLimit = 2}) {
  final details = <String>[artistAlbumCountLabel(artist)];
  details.addAll(_cleanGenres(artist.genres).take(genreLimit));
  return details.join(' / ');
}

String albumDetailLabel(Album album, {int genreLimit = 2}) {
  final details = <String>[];
  final year = album.year;
  if (year != null) {
    details.add(year.toString());
  }
  details.add(albumTrackCountLabel(album));
  details.addAll(_cleanGenres(album.genres).take(genreLimit));
  return details.join(' / ');
}

String albumMetaLabel(Album album) {
  final details = <String>[];
  final year = album.year;
  if (year != null) {
    details.add(year.toString());
  }
  details.add(albumTrackCountLabel(album));
  details.addAll(
    _cleanGenres(album.genres).take(3).map((g) => g.toUpperCase()),
  );
  return details.join(' / ');
}

String albumYearLabel(Album album) {
  return album.year?.toString() ?? 'YEAR UNKNOWN';
}

String albumGenresLabel(Album album) {
  final genres = _cleanGenres(album.genres).take(5).toList(growable: false);
  if (genres.isEmpty) {
    return 'UNKNOWN GENRE';
  }
  return genres.map((g) => g.toUpperCase()).join(' / ');
}

Iterable<String> _cleanGenres(Iterable<String> genres) sync* {
  for (final raw in genres) {
    final genre = raw.trim();
    if (genre.isNotEmpty) {
      yield genre;
    }
  }
}

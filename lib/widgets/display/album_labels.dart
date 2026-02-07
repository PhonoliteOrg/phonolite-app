import '../../entities/models.dart';

String albumMetaLabel(Album album) {
  final year = album.year?.toString();
  final genres = album.genres.isEmpty
      ? null
      : album.genres.map((g) => g.toUpperCase()).join(' • ');
  if (year == null || year.isEmpty) {
    return genres ?? 'UNKNOWN GENRE';
  }
  if (genres == null || genres.isEmpty) {
    return year;
  }
  return '$year • $genres';
}

String albumYearLabel(Album album) {
  return album.year?.toString() ?? 'YEAR UNKNOWN';
}

String albumGenresLabel(Album album) {
  if (album.genres.isEmpty) {
    return 'UNKNOWN GENRE';
  }
  return album.genres
      .take(5)
      .map((g) => g.toUpperCase())
      .join(' • ');
}

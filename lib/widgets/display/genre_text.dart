String genreBulletLine(Iterable<String> genres) {
  return genres
      .map((genre) => genre.trim())
      .where((genre) => genre.isNotEmpty)
      .map((genre) => genre.toUpperCase())
      .join(' \u2022 ');
}

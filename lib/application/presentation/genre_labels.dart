const _genreAcronyms = {
  'edm': 'EDM',
  'idm': 'IDM',
  'ebm': 'EBM',
  'aor': 'AOR',
  'mpb': 'MPB',
  'ost': 'OST',
  'ccm': 'CCM',
  'nwobhm': 'NWOBHM',
  'uk': 'UK',
  'us': 'US',
  'dj': 'DJ',
  'dnb': 'DnB',
  'rnb': 'RnB',
};

final _genreWhitespace = RegExp(r'\s+');

final _genreWord = RegExp(r'[^\s\-‐‑–—/&,;|()\[\]{}:]+');

/// Presentation only: matching keys, saved tags and listening events retain
/// their existing values, including for older cached/offline metadata.
String genreDisplayLabel(String value) {
  final normalized = value.trim().replaceAll(_genreWhitespace, ' ');

  String formatGenreWord(Match match) {
    final lower = match[0]!.toLowerCase();
    final acronym = _genreAcronyms[lower];
    if (acronym != null) {
      return acronym;
    }

    final result = StringBuffer();
    var capitalized = false;

    for (final rune in lower.runes) {
      final character = String.fromCharCode(rune);

      if (!capitalized && character.toLowerCase() != character.toUpperCase()) {
        result.write(character.toUpperCase());
        capitalized = true;
      } else {
        result.write(character);
      }
    }

    return result.toString();
  }

  return normalized.replaceAllMapped(_genreWord, formatGenreWord);
}

Iterable<String> displayGenres(Iterable<String> genres) sync* {
  final seen = <String>{};

  for (final raw in genres) {
    final genre = genreDisplayLabel(raw);

    if (genre.isNotEmpty && seen.add(genre.toLowerCase())) {
      yield genre;
    }
  }
}

String genreBulletLine(Iterable<String> genres) => displayGenres(genres).join(' \u2022 ');

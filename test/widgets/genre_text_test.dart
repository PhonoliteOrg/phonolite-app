import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/music/formatting/album_labels.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';

void main() {
  test('genre display casing handles words, acronyms and punctuation', () {
    const cases = {
      '  alternative   ROCK\t': 'Alternative Rock',
      'acid jazz': 'Acid Jazz',
      'r&b': 'R&B',
      'edm / idm / ebm': 'EDM / IDM / EBM',
      'dnb & rnb': 'DnB & RnB',
      'uk garage': 'UK Garage',
      'j-pop; k-pop': 'J-Pop; K-Pop',
      'post‐rock / nu-metal': 'Post‐Rock / Nu-Metal',
      'électronique (música clásica)': 'Électronique (Música Clásica)',
      '2-step': '2-Step',
      '東京': '東京',
      ' ': '',
    };
    for (final entry in cases.entries) {
      final actual = genreDisplayLabel(entry.key);
      expect(actual, entry.value, reason: entry.key);
      expect(
        genreDisplayLabel(actual),
        entry.value,
        reason: 'idempotent: ${entry.key}',
      );
    }
  });

  test(
    'cards, rows and hero labels format cached genres without mutating metadata',
    () {
      final genres = [
        ' alternative rock ',
        'ALTERNATIVE ROCK',
        '',
        'edm',
        'r&b',
      ];
      final original = List<String>.of(genres);
      final artist = Artist(
        id: 'artist',
        name: 'Artist',
        albumCount: 1,
        genres: genres,
      );
      final album = Album(
        id: 'album',
        title: 'Album',
        artist: 'Artist',
        artistId: 'artist',
        trackCount: 2,
        year: 2026,
        genres: genres,
      );
      expect(artistDetailLabel(artist), '1 album / Alternative Rock / EDM');
      expect(
        albumDetailLabel(album),
        '2026 / 2 tracks / Alternative Rock / EDM',
      );
      expect(
        albumMetaLabel(album),
        '2026 / 2 tracks / Alternative Rock / EDM / R&B',
      );
      expect(albumGenresLabel(album), 'Alternative Rock / EDM / R&B');
      expect(genreBulletLine(genres), 'Alternative Rock • EDM • R&B');
      expect(genres, original);
    },
  );
}

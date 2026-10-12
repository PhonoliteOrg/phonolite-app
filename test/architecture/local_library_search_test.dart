import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/local_library_search.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';

void main() {
  test(
    'server scoring vectors preserve Unicode, punctuation and match tiers',
    () {
      for (final vector in [
        ('東京', '東京', 100),
        ('東京', '大阪', 0),
        ('Björk', 'BJÖRK', 100),
        ('FIRST--LIGHT', 'First Light', 100),
        ('first', 'First Light', 90),
        ('light', 'First Light Alice', 80),
        ('alice first', 'First Light Alice', 70),
        ('frstlght', 'First Light', 60),
        ('unrelated', 'First Light', 0),
        ('!!!', 'First Light', 0),
      ]) {
        expect(
          scoreLibrarySearch(normalizeLibrarySearch(vector.$1), vector.$2),
          vector.$3,
          reason: '${vector.$1} vs ${vector.$2}',
        );
      }
    },
  );

  test(
    'local catalog returns ranked artists, albums and songs with album art',
    () {
      final tracks = [_track('a', 'Morning'), _track('b', 'Evening')];
      final groups = offlineArtistGroups(tracks);
      final results = searchLocalLibrary(
        query: 'Alice',
        tracks: tracks,
        artists: groups,
      );
      expect(results.map((r) => r.kind), ['artist', 'track', 'album', 'track']);
      expect(results.map((r) => r.title), [
        'Alice',
        'Evening',
        'First Light',
        'Morning',
      ]);
      expect(results.map((r) => r.score), [100, 80, 80, 80]);
      expect(results.first.artworkPath, 'artist.png');
      for (final result in results.skip(1)) {
        expect(result.albumId, 'album');
        expect(result.artworkPath, 'album.png');
      }
    },
  );

  test(
    'shared albums are listed once and tracks without ids reuse their cover',
    () {
      final tracks = [
        _track('a', 'Morning'),
        _track('b', 'Evening').copyWith(albumArtPath: null),
      ];
      final groups = offlineArtistGroups(tracks);
      final copy = OfflineArtistGroup(
        id: 'guest',
        name: 'Guest',
        albums: groups.single.albums,
      );
      final results = searchLocalLibrary(
        query: 'Light',
        tracks: tracks,
        artists: [...groups, copy],
      );
      expect(results.where((r) => r.kind == 'album'), hasLength(1));
      expect(results.where((r) => r.kind == 'track'), hasLength(2));
      expect(results.every((r) => r.artworkPath == 'album.png'), isTrue);

      final unidentified = tracks
          .map((t) => t.copyWith(albumId: null, offlineAlbum: null))
          .toList();
      final localGroups = offlineArtistGroups(unidentified);
      final localResults = searchLocalLibrary(
        query: 'Light',
        tracks: unidentified,
        artists: localGroups,
      );
      expect(
        localResults.every(
          (r) => r.albumId == localGroups.single.albums.single.id,
        ),
        isTrue,
      );
      expect(localResults.every((r) => r.artworkPath == 'album.png'), isTrue);
    },
  );

  test('same candidate substring filtering and result cap as server API', () {
    final tracks = [_track('a', 'Morning'), _track('b', 'Evening')];
    final groups = offlineArtistGroups(tracks);
    // The server filters its catalog before scoring; a fuzzy-only query does
    // not manufacture candidates that its catalog lookup would exclude.
    for (final query in ['frstlght', 'alice first', '!!!', ' ', 'absent']) {
      expect(
        searchLocalLibrary(query: query, tracks: tracks, artists: groups),
        isEmpty,
      );
    }
    expect(
      searchLocalLibrary(
        query: 'alice',
        tracks: tracks,
        artists: groups,
        limit: 2,
      ).map((r) => r.title),
      ['Alice', 'Evening'],
    );
    expect(searchLocalLibrary(query: '', tracks: [], artists: []), isEmpty);
  });

  test('track album id remains optional for legacy search payloads', () {
    final legacy = SearchResult.fromJson({
      'kind': 'track',
      'id': 'a',
      'title': 'Morning',
    });
    final current = SearchResult.fromJson({
      'kind': 'track',
      'id': 'a',
      'title': 'Morning',
      'album_id': 'album',
    });
    expect(legacy.albumId, isNull);
    expect(current.albumId, 'album');
  });
}

Track _track(String id, String title) => Track(
  id: id,
  title: title,
  artist: 'Alice',
  artistId: 'artist',
  album: 'First Light',
  albumId: 'album',
  durationMs: 60000,
  liked: false,
  inPlaylists: false,
  artistArtPath: 'artist.png',
  albumArtPath: 'album.png',
);

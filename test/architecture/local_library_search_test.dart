import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/queries/library/local_library_search.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';

void main() {
  test(
    'server scoring vectors preserve Unicode, punctuation and match tiers',
    () {
      // Identical vectors are consumed by Rust's matcher tests.
      final vectors =
          jsonDecode(
                File(
                  'test/fixtures/library_search_vectors.json',
                ).readAsStringSync(),
              )
              as List<dynamic>;
      for (final vector in vectors) {
        expect(
          scoreLibrarySearch(vector[0] as String, vector[1] as String),
          vector[2],
          reason: '${vector[0]} vs ${vector[1]}',
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

  test('fuzzy candidates survive filtering and retain the result cap', () {
    final tracks = [_track('a', 'Morning'), _track('b', 'Evening')];
    final groups = offlineArtistGroups(tracks);
    for (final query in ['frstlght', 'alice first', 'alic frst']) {
      final results = searchLocalLibrary(
        query: query,
        tracks: tracks,
        artists: groups,
      );
      expect(
        results.map((result) => result.kind),
        containsAll(['album', 'track']),
      );
    }
    for (final query in ['!!!', ' ', 'absent']) {
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

  test('all single letter edits work without spelling-specific rules', () {
    const word = 'radiohead';
    for (var i = 0; i < word.length; i++) {
      final variants = [
        word.substring(0, i) + word.substring(i + 1),
        '${word.substring(0, i)}x${word.substring(i + 1)}',
        '${word.substring(0, i)}x${word.substring(i)}',
        if (i + 1 < word.length)
          word.substring(0, i) + word[i + 1] + word[i] + word.substring(i + 2),
      ];
      for (final query in variants) {
        expect(scoreLibrarySearch(query, word), greaterThan(0), reason: query);
      }
    }
  });

  test('long literal queries work without unbounded fuzzy comparisons', () {
    final query = LibrarySearchQuery('a' * 5000);
    expect(query.score('a' * 5000), 100);
    expect(query.score('b' * 5000), 0);
  });

  test('punctuation and spacing equivalence preserves display and artwork', () {
    final track = _track('a', 'Don’t Stop').copyWith(artist: 'Guns N’ Roses');
    final groups = offlineArtistGroups([track]);
    for (final query in ['dont stop', 'dontstop', 'dontstp', 'dont stpo']) {
      final result = searchLocalLibrary(
        query: query,
        tracks: [track],
        artists: groups,
      ).singleWhere((result) => result.kind == 'track');
      expect(result.title, 'Don’t Stop');
      expect(result.artworkPath, 'album.png');
      expect(result.albumId, 'album');
    }
    expect(
      searchLocalLibrary(
        query: 'gunsnroses',
        tracks: [track],
        artists: groups,
      ).any((result) => result.kind == 'artist'),
      isTrue,
    );
  });

  test('ranking considers matches beyond the old per-kind candidate cap', () {
    final tracks = [
      for (var i = 0; i < 60; i++)
        _track('early-$i', 'Moonlight $i').copyWith(trackNo: i + 1),
      _track('late', 'Light').copyWith(trackNo: 100),
    ];
    final result = searchLocalLibrary(
      query: 'light',
      tracks: tracks,
      artists: [],
      limit: 1,
    );
    expect(result.single.id, 'late');
    expect(result.single.score, 90);
  });

  test('identifiers and ordering numbers do not become fuzzy search terms', () {
    final track = _track(
      'secretidentifier',
      'Morning',
    ).copyWith(trackNo: 54321);
    for (final query in ['secretidentifier', '54321', '9999']) {
      expect(
        searchLocalLibrary(
          query: query,
          tracks: [track],
          artists: offlineArtistGroups([track]),
        ),
        isEmpty,
      );
    }
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

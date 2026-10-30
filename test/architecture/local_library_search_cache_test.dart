import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/queries/library/local_library_search.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

class _Connection extends Fake implements ServerConnection {
  @override
  int sessionRevision = 0;
}

class _App extends Fake implements AppController {
  @override
  final _Connection connection = _Connection();
  final authEvents = StreamController<AuthState>.broadcast(sync: true);
  @override
  final authState = AuthState(isAuthorized: false, baseUrl: 'https://music.test:3000');
  @override
  Stream<AuthState> get authStream => authEvents.stream;
}

/// Counts actual catalogue reads, rather than timing a small test fixture.
class _ReadCountingList<T> extends ListBase<T> {
  final List<T> _items;
  int reads = 0;

  _ReadCountingList(this._items);

  @override
  int get length => _items.length;
  @override
  set length(int value) => _items.length = value;
  @override
  T operator [](int index) {
    reads++;
    return _items[index];
  }

  @override
  void operator []=(int index, T value) => _items[index] = value;

  @override
  void add(T value) => _items.add(value);
}

void main() {
  late _App app;
  late LibraryController controller;
  late _ReadCountingList<Track> tracks;
  late _ReadCountingList<OfflineArtistGroup> groups;

  setUp(() {
    app = _App();
    controller = LibraryController(app)..setQuery('Alice');
    final source = [_track('first', 'Morning'), _track('second', 'Evening')];
    tracks = _ReadCountingList(source);
    groups = _ReadCountingList(offlineArtistGroups(source));
  });

  tearDown(() async {
    controller.dispose();
    await app.authEvents.close();
  });

  test('repeated snapshot searches reuse results without reading the catalogue', () {
    final first = controller.localResults(tracks, groups, revision: 1);
    final trackReads = tracks.reads;
    final artistReads = groups.reads;

    controller.setQuery('  ALICE!!!  ');
    final second = controller.localResults(tracks, groups, revision: 1);

    expect(_rows(second), _rows(first));
    expect(tracks.reads, trackReads);
    expect(groups.reads, artistReads);
    expect(identical(first, second), isFalse);

    // A consumer may replace entries in its own fixed-length result list.
    first[0] = SearchResult(kind: 'track', id: 'changed', title: 'Changed');
    expect(controller.localResults(tracks, groups, revision: 1).first.id, 'artist');
  });

  test('a new revision refreshes metadata even when input list identities stay the same', () {
    controller.localResults(tracks, groups, revision: 1);
    tracks[0] = tracks[0].copyWith(title: 'New Morning', albumArtPath: 'new-cover.png');
    groups[0] = offlineArtistGroups(tracks).single;
    final before = tracks.reads;

    final results = controller.localResults(tracks, groups, revision: 2);

    expect(tracks.reads, greaterThan(before));
    expect(_rows(results), _rows(searchLocalLibrary(query: 'Alice', tracks: tracks, artists: groups)));
    expect(results.singleWhere((result) => result.id == 'first').title, 'New Morning');
  });

  test('replaced catalogue lists invalidate an equal revision', () {
    controller.localResults(tracks, groups, revision: 1);
    final replacement = [_track('third', 'Afternoon')];
    final results = controller.localResults(replacement, offlineArtistGroups(replacement), revision: 1);

    expect(results.where((result) => result.kind == 'track').map((result) => result.id), ['third']);
  });

  test('mutable callers without a snapshot revision always get fresh results', () {
    controller.localResults(tracks, groups);
    tracks.add(_track('third', 'Afternoon'));
    groups[0] = offlineArtistGroups(tracks).single;

    final results = controller.localResults(tracks, groups);

    expect(results.any((result) => result.id == 'third'), isTrue);
  });

  test('only the most recent query page is retained', () {
    controller.localResults(tracks, groups, revision: 1);
    controller.setQuery('Evening');
    controller.localResults(tracks, groups, revision: 1);
    final before = tracks.reads;

    controller.setQuery('Alice');
    controller.localResults(tracks, groups, revision: 1);

    expect(tracks.reads, greaterThan(before));
  });

  test('account-session changes discard the cached page', () {
    controller.localResults(tracks, groups, revision: 1);
    final before = tracks.reads;
    app.connection.sessionRevision++;
    app.authEvents.add(app.authState);

    controller.localResults(tracks, groups, revision: 1);

    expect(tracks.reads, greaterThan(before));
  });

  test('nonmatches do not change Unicode catalogue ordering for tied matches', () {
    final tied = [
      _track('astral', 'Same').copyWith(artist: '𐐀', artistId: 'astral', album: 'Record'),
      _track('private', 'Same').copyWith(artist: '\uE000', artistId: 'private', album: 'Record'),
      _track('greek', 'Same').copyWith(artist: 'α', artistId: 'greek', album: 'Record'),
      _track('ascii', 'Same').copyWith(artist: 'Alice', album: 'Record'),
    ];
    final catalogue = [
      for (var i = 0; i < 150; i++)
        _track('unmatched-$i', 'Unrelatedzzzz $i').copyWith(artist: 'Quietzzzz', album: 'Otherzzzz'),
      ...tied,
    ];
    final results = searchLocalLibrary(query: 'same', tracks: catalogue, artists: []);

    expect(results.map((result) => result.id), ['ascii', 'greek', 'private', 'astral']);
    expect(results.map((result) => result.score), everyElement(90));
  });
}

List<Object?> _rows(List<SearchResult> results) => [
  for (final result in results)
    [result.kind, result.id, result.title, result.subtitle, result.score, result.albumId, result.artworkPath],
];

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

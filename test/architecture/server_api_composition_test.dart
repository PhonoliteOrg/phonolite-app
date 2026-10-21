import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('endpoint clients share the current transport session', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode([]), 200);
    });
    addTearDown(client.close);
    final connection = ServerConnection(baseUrl: 'http://first.test/api/v1', client: client)..setToken('first-token');

    await connection.fetchArtistsPage();
    await connection.fetchPlaylists();
    final revision = connection.sessionRevision;
    connection.setBaseUrl('http://second.test/api/v1');
    connection.setToken('second-token');
    await connection.fetchArtistsPage();
    await connection.fetchPlaylists();

    expect(connection.sessionRevision, greaterThan(revision));
    expect(requests.map((request) => request.url.host), ['first.test', 'first.test', 'second.test', 'second.test']);
    expect(requests.map((request) => request.headers['Authorization']), [
      'Bearer first-token',
      'Bearer first-token',
      'Bearer second-token',
      'Bearer second-token',
    ]);
  });

  test('composed collection calls preserve connection overrides', () async {
    final connection = _OverriddenLikesConnection();
    final state = await connection.setLikeState('track', true);
    expect(connection.updates, [
      {'track': true},
    ]);
    expect(state?.trackId, 'track');
    expect(state?.liked, isTrue);
  });

  test('pagination retains facade overrides for every page', () async {
    final client = MockClient((request) async => throw StateError('Unexpected network request: ${request.url}'));
    addTearDown(client.close);
    final connection = _OverriddenEndpointsConnection(client);

    final artists = await connection.fetchArtists(limit: 2, includeContributors: true);

    expect(connection.artistOffsets, [0, 2]);
    expect(artists.map((artist) => artist.id), ['artist-0', 'artist-1', 'artist-2']);
  });

  test('artwork and download operations retain overridden URL builders', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);

      return http.Response('image', 200, headers: {'content-type': 'image/png'});
    });
    addTearDown(client.close);
    final connection = _OverriddenEndpointsConnection(client);

    await connection.fetchAlbumCoverBytes('album');
    await connection.fetchArtistCoverBytes('artist', kind: 'banner');
    await connection.fetchPlaylistCoverBytes('playlist', imageRef: 'version');
    expect(connection.buildDownloadUrl('track'), 'https://override.test/download/track');

    final download = await connection.openTrackDownload('track');
    await download.stream.drain<void>();

    expect(requests.map((uri) => uri.toString()), [
      'https://override.test/album/album',
      'https://override.test/artist/artist?kind=banner',
      'https://override.test/playlist/playlist?ref=version',
      'https://override.test/download/track',
    ]);
  });
}

class _OverriddenEndpointsConnection extends ServerConnection {
  final List<int> artistOffsets = [];

  _OverriddenEndpointsConnection(http.Client client) : super(baseUrl: 'https://original.test/api/v1', client: client);

  @override
  Future<List<Artist>> fetchArtistsPage({
    int limit = ServerConnection.artistsPageSize,
    int offset = 0,
    bool includeContributors = false,
  }) async {
    expect(limit, 2);
    expect(includeContributors, isTrue);
    artistOffsets.add(offset);

    return [
      for (var index = offset; index < offset + (offset == 0 ? 2 : 1); index++)
        Artist(id: 'artist-$index', name: 'Artist $index', albumCount: 0),
    ];
  }

  @override
  String buildAlbumCoverUrl(String albumId) => 'https://override.test/album/$albumId';

  @override
  String buildArtistCoverUrl(String artistId, {String? kind, String? ref}) =>
      'https://override.test/artist/$artistId?kind=$kind';

  @override
  String buildPlaylistCoverUrl(String playlistId, {String? imageRef}) =>
      'https://override.test/playlist/$playlistId?ref=$imageRef';

  @override
  String buildTrackDownloadUrl(String trackId) => 'https://override.test/download/$trackId';
}

class _OverriddenLikesConnection extends ServerConnection {
  _OverriddenLikesConnection() : super(baseUrl: 'http://example.test/api/v1');
  final updates = <Map<String, bool>>[];

  @override
  Future<List<ServerLikeState>> updateLikeStates(
    Map<String, bool> states, {
    Map<String, int> updatedAtByTrack = const {},
  }) async {
    updates.add(Map.of(states));
    return [for (final entry in states.entries) ServerLikeState(trackId: entry.key, liked: entry.value, updatedAt: 1)];
  }
}

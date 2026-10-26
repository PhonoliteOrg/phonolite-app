import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('shuffle creation, pages and release preserve account/client identity and ten-ID limits', () async {
    final requests = <http.Request>[];
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response(
          jsonEncode({
            'session_id': 'session /id',
            'offset': 0,
            'next_offset': 10,
            'total': 20,
            'has_more': true,
            'items': [offlineTestTrack(id: 'track').toJson()],
            'item_offsets': [7],
          }),
          200,
        );
      }),
    );
    connection.setToken('account-token');
    final first = await connection.createShuffleSession(
      mode: 'custom',
      clientId: 'client /id',
      requestId: 'request-unique',
      artistId: 'artist',
      albumId: 'album',
      artistIds: ['artist-a', 'artist-b'],
      genres: ['drum and bass'],
      playlistId: 'playlist',
      startTrackId: 'track',
    );
    expect(first.items.single.id, 'track');
    expect(first.itemOffsets, [7]);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body, {
      'mode': 'custom',
      'client_id': 'client /id',
      'request_id': 'request-unique',
      'limit': 10,
      'artist_id': 'artist',
      'album_id': 'album',
      'artist_ids': ['artist-a', 'artist-b'],
      'genres': ['drum and bass'],
      'playlist_id': 'playlist',
      'start_track_id': 'track',
    });
    await connection.fetchShuffleSessionPage(first.sessionId, clientId: 'client /id', offset: 10);
    expect(requests.last.url.pathSegments.last, 'session /id');
    expect(requests.last.url.queryParameters, {'client_id': 'client /id', 'offset': '10', 'limit': '10'});
    await connection.releaseShuffleSession(first.sessionId, clientId: 'client /id');
    expect(requests.last.method, 'DELETE');
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer account-token'), isTrue);
    expect(requests.map((request) => request.method), ['POST', 'GET', 'DELETE']);
  });
}

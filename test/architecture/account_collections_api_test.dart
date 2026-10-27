import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('atomic track changes and ordered replacement send distinct contracts', () async {
    final requests = <http.Request>[];
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((request) async {
        requests.add(request);

        return http.Response(
          jsonEncode({
            'id': 'mix',
            'name': 'Mix',
            'track_ids': ['track'],
            'revision': 8,
          }),
          200,
        );
      }),
    );
    addTearDown(connection.close);

    final added = await connection.addPlaylistTracks('mix one', ['track']);
    await connection.removePlaylistTracks('mix one', ['track']);
    await connection.replacePlaylistTracks('mix one', ['track'], expectedRevision: 7);

    expect(added.revision, 8);
    expect(requests.map((request) => request.method), ['POST', 'DELETE', 'POST']);
    expect(requests[0].url.toString(), 'https://server.test/api/library/playlists/mix%20one/tracks');
    expect(requests[1].url, requests[0].url);
    expect(requests[1].headers['content-type'], 'application/json');
    expect(jsonDecode(requests[0].body), {
      'track_ids': ['track'],
    });
    expect(jsonDecode(requests[1].body), {
      'track_ids': ['track'],
    });
    expect(jsonDecode(requests[2].body), {
      'track_ids': ['track'],
      'expected_revision': 7,
    });
  });

  test('a late metadata response uses the latest collection snapshot', () async {
    final response = Completer<http.Response>();
    final track = offlineTestTrack(id: 'track');
    final connection = ServerConnection(baseUrl: 'https://server.test/api', client: MockClient((_) => response.future));
    addTearDown(connection.close);
    connection.setToken('account');

    final pending = connection.fetchTrackById('track');
    connection.applyCollectionSnapshot(_snapshot(liked: true));
    response.complete(http.Response(jsonEncode(track.toJson()), 200));
    final updated = await pending;

    expect(updated.liked, isTrue);
    expect(updated.inPlaylists, isTrue);
    expect(updated.title, track.title);
  });

  test('account changes clear projection and do not apply a new account to old reads', () async {
    final response = Completer<http.Response>();
    final track = offlineTestTrack(id: 'track');
    final connection = ServerConnection(baseUrl: 'https://server.test/api', client: MockClient((_) => response.future));
    addTearDown(connection.close);
    connection.setToken('first');
    connection.applyCollectionSnapshot(_snapshot(liked: true));
    expect(connection.projectServerTrack(track).liked, isTrue);

    final pending = connection.fetchTrackById('track');
    connection.setToken('second');
    expect(connection.projectServerTrack(track).liked, isFalse);
    connection.applyCollectionSnapshot(_snapshot(liked: true));
    response.complete(http.Response(jsonEncode(track.toJson()), 200));

    expect((await pending).liked, isFalse);
    expect(connection.projectServerTrack(track).liked, isTrue);
  });

  test('list and shuffle reads project flags while preserving shuffle offsets', () async {
    final track = offlineTestTrack(id: 'track');
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((request) async {
        final value = request.url.path.contains('/shuffle/sessions')
            ? <String, Object>{
                'session_id': 'session',
                'offset': 10,
                'next_offset': 11,
                'total': 20,
                'has_more': true,
                'items': [track.toJson()],
                'item_offsets': [10],
              }
            : <String, Object>{
                'items': [track.toJson()],
                'total': 1,
              };

        return http.Response(jsonEncode(value), 200);
      }),
    );
    addTearDown(connection.close);
    connection.setToken('account');
    connection.applyCollectionSnapshot(_snapshot(liked: true));

    final reads = await Future.wait([
      connection.fetchTracks('album'),
      connection.fetchPlaylistTracks('mix'),
      connection.fetchLikedTracks(),
      connection.fetchShuffleTracks(mode: 'all'),
    ]);

    for (final tracks in reads) {
      expect(tracks.single.liked, isTrue);
      expect(tracks.single.inPlaylists, isTrue);
    }

    final page = await connection.fetchShuffleSessionPage('session', clientId: 'client', offset: 10);

    expect(page.items.single.liked, isTrue);
    expect(page.items.single.inPlaylists, isTrue);
    expect(page.itemOffsets, [10]);
    expect(page.offset, 10);
    expect(page.nextOffset, 11);
    expect(page.hasMore, isTrue);
  });
}

AccountCollectionSnapshot _snapshot({required bool liked}) => AccountCollectionSnapshot(
  userId: 'account',
  revision: 1,
  likes: [ServerLikeState(trackId: 'track', liked: liked, updatedAt: 1)],
  playlists: [
    Playlist(id: 'mix', name: 'Mix', trackIds: ['track'], revision: 1),
  ],
);

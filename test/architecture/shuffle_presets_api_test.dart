import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset_snapshot.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('preset requests retain revisions, account headers and encoded IDs', () async {
    final requests = <http.Request>[];
    final presetJson = <String, dynamic>{
      'id': 'mix / one',
      'name': 'Night music',
      'artist_ids': ['artist'],
      'genres': ['ambient'],
      'revision': 4,
    };
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        requests.add(request);

        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }

        return http.Response(
          jsonEncode(
            request.method == 'GET'
                ? {
                    'revision': 9,
                    'items': [presetJson],
                  }
                : presetJson,
          ),
          200,
        );
      }),
    );
    addTearDown(connection.close);
    connection.setToken('this-account');

    final snapshot = await connection.fetchShufflePresets();
    final created = await connection.createShufflePreset(
      name: 'Night music',
      artistIds: ['artist'],
      genres: ['ambient'],
    );
    await connection.updateShufflePreset(
      'mix / one',
      name: 'Night music',
      artistIds: ['artist'],
      genres: ['ambient'],
      expectedRevision: 3,
    );
    await connection.deleteShufflePreset('mix / one', expectedRevision: 4);

    expect(snapshot.revision, 9);
    expect(snapshot.items.single.name, 'Night music');
    expect(created.revision, 4);
    expect(requests.map((request) => request.method), ['GET', 'POST', 'POST', 'DELETE']);
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer this-account'), isTrue);
    expect(requests[2].url.toString(), 'https://music.test/api/account/shuffle-presets/mix%20%2F%20one');
    expect(jsonDecode(requests[1].body), {
      'name': 'Night music',
      'artist_ids': ['artist'],
      'genres': ['ambient'],
    });
    expect(jsonDecode(requests[2].body), {
      'name': 'Night music',
      'artist_ids': ['artist'],
      'genres': ['ambient'],
      'expected_revision': 3,
    });
    expect(requests[3].url.queryParameters, {'expected_revision': '4'});
  });

  test('preset and snapshot values cannot be changed by their input lists', () {
    final artists = ['artist'];
    final genres = ['ambient'];
    final preset = ShufflePreset(id: 'id', name: 'Name', artistIds: artists, genres: genres, revision: 1);
    final items = [preset];
    final snapshot = ShufflePresetSnapshot(revision: 2, items: items);

    artists.clear();
    genres.clear();
    items.clear();

    expect(preset.artistIds, ['artist']);
    expect(preset.genres, ['ambient']);
    expect(snapshot.items.single, same(preset));
    expect(() => preset.artistIds.add('other'), throwsUnsupportedError);
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
    expect(ShufflePresetSnapshot.fromJson(snapshot.toJson()).items.single.toJson(), preset.toJson());
  });
}

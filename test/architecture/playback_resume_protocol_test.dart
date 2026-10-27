import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/auth/account_state.dart';
import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/device_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/playback/playback_source_context.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('checkpoint codecs are strict, immutable, and preserve explicit deck clearing', () {
    final artists = ['artist'];
    final context = PlaybackSourceContext(kind: 'custom', artistIds: artists, genres: ['jazz']);
    final original = _checkpoint().copyWith(shuffleContext: context, deckId: 'deck');
    artists.add('unexpected');

    expect(context.artistIds, ['artist']);
    expect(() => context.artistIds.add('other'), throwsUnsupportedError);
    expect(PlaybackResumeCheckpoint.fromJson(original.toJson()), original);
    expect(original.copyWith().deckId, 'deck');
    expect(original.copyWith(deckId: null).deckId, isNull);
    expect(() => PlaybackSourceContext(kind: 'unknown'), throwsFormatException);
    expect(() => PlaybackSourceContext(kind: 'playlist'), throwsFormatException);
    expect(() => PlaybackResumeCheckpoint.fromJson({...original.toJson(), 'cursor': -1}), throwsFormatException);
    expect(() => PlaybackResumeCheckpoint.fromJson({...original.toJson(), 'cursor': 1.5}), throwsFormatException);
    expect(
      () => PlaybackResumeCheckpoint.fromJson({...original.toJson(), 'shuffle_mode': 'future'}),
      throwsFormatException,
    );
  });

  test('device snapshots reject unknown schema and keep duplicate queue occurrences', () {
    final original = DevicePlaybackSnapshot(checkpoint: _checkpoint(), queueTrackIds: ['a', 'b', 'a']);

    expect(DevicePlaybackSnapshot.fromJson(original.toJson()).queueTrackIds, ['a', 'b', 'a']);
    expect(() => DevicePlaybackSnapshot.fromJson({...original.toJson(), 'schema_version': 2}), throwsFormatException);
    expect(() => DevicePlaybackSnapshot.fromJson({...original.toJson(), 'position_ms': -1}), throwsFormatException);
    expect(
      () => DevicePlaybackSnapshot.fromJson({
        ...original.toJson(),
        'queue_track_ids': [true],
      }),
      throwsFormatException,
    );
  });

  test('account protocol sends coherent IDs and rules without device-only state', () async {
    final requests = <http.Request>[];
    final checkpoint = _checkpoint();
    final snapshot = AccountPlaybackSnapshot(revision: 7, generation: 'generation', checkpoint: checkpoint);
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        requests.add(request);

        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }

        if (request.url.path.contains('/decks/')) {
          return http.Response(
            jsonEncode({
              'session_id': 'deck / id',
              'offset': 10,
              'next_offset': 20,
              'total': 30,
              'has_more': true,
              'items': [],
              'item_offsets': [],
            }),
            200,
          );
        }

        return http.Response(jsonEncode(snapshot.toJson()), 200);
      }),
    );
    connection.setToken('private-token');

    expect((await connection.fetchAccountPlayback()).checkpoint, checkpoint);
    await connection.saveAccountPlayback(
      expectedRevision: 6,
      sessionId: 'writer',
      sequence: 3,
      requestId: 'retry-id',
      intent: 'update',
      generation: 'generation',
      clientId: 'runtime-client',
      checkpoint: checkpoint,
    );

    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body, {
      'expected_revision': 6,
      'session_id': 'writer',
      'sequence': 3,
      'request_id': 'retry-id',
      'intent': 'update',
      'generation': 'generation',
      'client_id': 'runtime-client',
      'checkpoint': checkpoint.toJson(),
    });
    expect(body['checkpoint']['shuffle_mode'], 'current_playlist');
    expect(body.keys, isNot(contains('user_id')));
    expect(requests.last.body, isNot(contains('file_path')));
    expect(requests.last.body, isNot(contains('queue_track_ids')));
    expect(requests.last.body, isNot(contains('position_ms')));

    await connection.fetchAccountPlaybackDeck('deck / id', offset: 10);
    expect(requests.last.url.pathSegments.last, 'deck / id');
    expect(requests.last.url.queryParameters, {'offset': '10', 'limit': '10'});

    await connection.clearAccountPlayback(expectedRevision: 7);
    expect(requests.last.url.queryParameters, {'expected_revision': '7'});
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer private-token'), isTrue);
  });

  test('account conflicts propagate rather than silently retry stale writes', () async {
    var attempts = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        attempts++;

        return http.Response('{"error":"playback revision changed"}', 409);
      }),
    );

    await expectLater(
      connection.saveAccountPlayback(
        expectedRevision: 1,
        sessionId: 'writer',
        sequence: 1,
        requestId: 'id',
        intent: 'start',
        checkpoint: _checkpoint(),
      ),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'status', 409)),
    );
    expect(attempts, 1);
  });

  test('new playback capabilities and revision clocks tolerate old servers', () {
    expect(ServerCapabilities.fromJson({'playback_resume': '1'}).playbackResume, isTrue);
    expect(ServerCapabilities.fromJson({}).playbackResume, isFalse);
    final old = AccountRevisions.fromJson({'collections': 1, 'presets': 2, 'statistics': 3});
    final newer = AccountRevisions.fromJson({'collections': 1, 'presets': 2, 'statistics': 3, 'playback': 4});

    expect(old.playback, 0);
    expect(newer.isAheadOf(old), isTrue);
    expect(old.isBehind(newer), isTrue);
    expect(old.merge(newer).playback, 4);
    expect(
      AccountPlaybackSnapshot.fromJson({'revision': 2, 'checkpoint': null, 'reason': 'source_empty'}).checkpoint,
      isNull,
    );
  });
}

PlaybackResumeCheckpoint _checkpoint() => PlaybackResumeCheckpoint(
  trackId: 'server-track',
  source: PlaybackSourceContext(kind: 'playlist', id: 'mix'),
  shuffleMode: ShuffleMode.currentPlaylist,
  shuffleContext: PlaybackSourceContext(kind: 'playlist', id: 'mix'),
  deckId: 'deck / id',
  cursor: 17,
);

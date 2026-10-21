import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('server addresses resolve to the shared API baseline', () async {
    final connection = ServerConnection(baseUrl: 'https://music.test:3000/api');

    for (final address in ['music.test:3000', 'https://music.test:3000/', 'https://music.test:3000/api/']) {
      expect(await connection.resolveBaseUrl(address), 'https://music.test:3000/api');
    }
  });

  test('download job requests and returned file URLs share the API baseline', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode({'job_id': 'job/id'}), 200);
    });
    addTearDown(client.close);
    final connection = ServerConnection(baseUrl: 'https://music.test/api', client: client)..setToken('token');

    final job = await connection.createDownloadJob(
      clientId: 'device/id',
      clientRequestId: 'request',
      scope: DownloadJobScopeV2(kind: 'tracks', trackIds: ['track/id']),
    );
    await connection.fetchDownloadJobs(clientId: 'device/id', scopeKind: 'artist', scopeId: 'artist/id');
    await connection.applyDownloadJobAction(jobId: job.jobId, action: 'delete');

    expect(requests.map((request) => '${request.method} ${request.url}'), [
      'POST https://music.test/api/download/jobs',
      'GET https://music.test/api/download/jobs?client_id=device%2Fid&scope_kind=artist&scope_id=artist%2Fid',
      'POST https://music.test/api/download/jobs/job%2Fid/actions',
    ]);
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer token'), isTrue);
    expect(jsonDecode(requests.first.body)['scope'], {
      'kind': 'tracks',
      'track_ids': ['track/id'],
    });
    expect(jsonDecode(requests.last.body), {'action': 'delete'});

    for (final url in [
      '/api/download/tracks/track%2Fid/file',
      '/download/tracks/track%2Fid/file',
      'download/tracks/track%2Fid/file',
      'https://music.test/api/download/tracks/track%2Fid/file',
    ]) {
      expect(
        connection.buildDownloadUrl('track/id', downloadUrl: url),
        'https://music.test/api/download/tracks/track%2Fid/file',
      );
    }
    expect(connection.buildTrackDownloadUrl('track/id'), 'https://music.test/api/download/tracks/track%2Fid');
  });

  test('listening counter requests use the shared API baseline', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final connection = ServerConnection(baseUrl: 'https://music.test/api', client: client)..setToken('token');

    await connection.fetchListeningCounterState(deviceId: 'device/id');
    await connection.activateListeningCounters(deviceId: 'device/id', historyGeneration: 7);
    await connection.uploadListeningCounters({'device_id': 'device/id', 'batch_sequence': 2});
    await connection.fetchListeningCounterSnapshot(
      deviceId: 'device/id',
      year: 2026,
      month: 10,
      revision: 3,
      after: 'next/key',
    );

    expect(requests.map((request) => '${request.method} ${request.url}'), [
      'GET https://music.test/api/stats/state?device_id=device%2Fid',
      'POST https://music.test/api/stats/activate',
      'POST https://music.test/api/stats/batch',
      'GET https://music.test/api/stats/snapshot?device_id=device%2Fid&year=2026&month=10&after=next%2Fkey&revision=3',
    ]);
    expect(jsonDecode(requests[1].body), {'device_id': 'device/id', 'history_generation': 7});
    expect(jsonDecode(requests[2].body), {'device_id': 'device/id', 'batch_sequence': 2});
  });
}

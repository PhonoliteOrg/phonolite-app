import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('overlapping entity reads share HTTP and decode, later reads refresh', () async {
    final released = Completer<void>();
    final seen = <String>[];
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((request) async {
        seen.add(request.url.path);
        await released.future;
        final metadata = offlineTestOfflineMetadata(trackId: 'track');
        final value = request.url.path.endsWith('/offline-metadata')
            ? metadata.toJson()
            : request.url.path.contains('/albums/')
            ? metadata.album.toJson()
            : request.url.path.contains('/artists/')
            ? metadata.artist.toJson()
            : metadata.track.toJson();
        return http.Response(jsonEncode(value), 200);
      }),
    );
    final reads = <Future<Object>>[
      for (var i = 0; i < 6; i++) ...[
        connection.fetchTrackById('track'),
        connection.fetchAlbumById('album'),
        connection.fetchArtistById('artist'),
        connection.fetchOfflineMetadata('track'),
      ],
    ];
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(4));
    released.complete();
    expect(await Future.wait(reads), hasLength(24));
    await connection.fetchTrackById('track');
    expect(seen, hasLength(5));
  });

  test('failed shared reads are evicted for the next attempt', () async {
    final released = Completer<void>();
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          await released.future;
          return http.Response('missing', 404);
        }
        return http.Response(jsonEncode(offlineTestTrack(id: 'track').toJson()), 200);
      }),
    );
    final first = connection.fetchTrackById('track');
    final second = connection.fetchTrackById('track');
    final failures = <Future<void>>[
      expectLater(first, throwsA(isA<ApiException>())),
      expectLater(second, throwsA(isA<ApiException>())),
    ];
    released.complete();
    await Future.wait(failures);
    expect(requests, 1);
    expect((await connection.fetchTrackById('track')).id, 'track');
    expect(requests, 2);
  });

  test('shared metadata failures preserve their error and stack before retrying', () async {
    final transport = _ControlledMetadataTransport();
    addTearDown(transport.client.close);

    Future<({Object error, StackTrace stackTrace})> captureFailure(Future<Map<String, dynamic>> pending) async {
      try {
        await pending;
      } catch (error, stackTrace) {
        return (error: error, stackTrace: stackTrace);
      }

      throw StateError('Expected the metadata read to fail');
    }

    final first = transport.getMetadata('/metadata');
    final second = transport.getMetadata('/metadata');
    final error = StateError('Metadata failed');
    final stackTrace = StackTrace.fromString('original metadata failure');
    final failures = Future.wait([captureFailure(first), captureFailure(second)]);

    expect(second, same(first));
    expect(transport.requests, hasLength(1));
    transport.requests.single.completeError(error, stackTrace);

    for (final failure in await failures) {
      expect(failure.error, same(error));
      expect(failure.stackTrace.toString(), stackTrace.toString());
    }

    final retried = transport.getMetadata('/metadata');
    final response = <String, dynamic>{'id': 'fresh'};

    expect(transport.requests, hasLength(2));
    transport.requests.last.complete(response);
    expect(await retried, same(response));
  });

  test('server and credential changes separate overlapping reads', () async {
    final pending = <Completer<http.Response>>[];
    final seen = <http.Request>[];
    final connection = ServerConnection(
      baseUrl: 'https://first.test/api',
      client: MockClient((request) {
        seen.add(request);
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      }),
    );
    connection.setToken('old');
    final old = connection.fetchTrackById('track');
    connection.setToken('new');
    final newToken = connection.fetchTrackById('track');
    connection.setBaseUrl('https://second.test/api');
    expect(connection.token, isNull);

    final newServer = connection.fetchTrackById('track');
    await Future<void>.delayed(Duration.zero);
    expect(seen.map((item) => item.url.host), ['first.test', 'first.test', 'second.test']);
    expect(seen.map((item) => item.headers['Authorization']), ['Bearer old', 'Bearer new', null]);
    for (final item in pending) {
      item.complete(http.Response(jsonEncode(offlineTestTrack(id: 'track').toJson()), 200));
    }
    await Future.wait([old, newToken, newServer]);
  });

  test('old completion cannot evict a newer request for the same path', () async {
    final pending = <Completer<http.Response>>[];
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((_) {
        requests++;
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      }),
    );
    final old = connection.fetchTrackById('track');
    connection.setToken('new');
    final current = connection.fetchTrackById('track');
    await Future<void>.delayed(Duration.zero);
    final response = http.Response(jsonEncode(offlineTestTrack(id: 'track').toJson()), 200);
    pending.first.complete(response);
    await old;
    final alsoCurrent = connection.fetchTrackById('track');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    pending.last.complete(response);
    await Future.wait([current, alsoCurrent]);
  });

  test('a retry retains its original server and credentials', () async {
    final seen = <http.Request>[];
    late final ServerConnection connection;
    connection = ServerConnection(
      baseUrl: 'https://first.test/api',
      client: MockClient((request) async {
        seen.add(request);
        if (seen.length == 1) {
          connection.setBaseUrl('https://second.test/api');
          connection.setToken('new');
          return http.Response('retry', 503);
        }
        return http.Response(jsonEncode(offlineTestTrack(id: 'track').toJson()), 200);
      }),
    );
    connection.setToken('old');
    await connection.fetchTrackById('track');
    expect(seen.map((item) => item.url.host), ['first.test', 'first.test']);
    expect(seen.map((item) => item.headers['Authorization']), ['Bearer old', 'Bearer old']);
  });

  test('private artwork stops retrying when its originating account changes', () async {
    final seen = <http.Request>[];
    late final ServerConnection connection;
    connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((request) async {
        seen.add(request);
        if (seen.length == 1) {
          connection.setToken('new-account');
          return http.Response('retry', 503);
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    connection.setToken('old-account');
    await expectLater(connection.fetchPlaylistCoverBytes('old-private-playlist'), throwsA(isA<StateError>()));
    expect(seen.map((item) => item.headers['Authorization']), ['Bearer old-account']);
    expect(connection.token, 'new-account');
  });

  test('late transport failures from the old account cannot invalidate the current session', () async {
    final failed = Completer<http.Response>();
    final transport = ApiTransport(baseUrl: 'https://server.test/api', client: MockClient((_) => failed.future));
    var failures = 0;
    transport.onTransportFailure = (_) => failures++;
    transport.setToken('old-account');
    final request = transport.get('/player/settings', retryable: false);
    final rejected = expectLater(request, throwsA(isA<http.ClientException>()));
    await Future<void>.delayed(Duration.zero);
    transport.setToken('new-account');
    failed.completeError(http.ClientException('Old account disconnected'));
    await rejected;
    expect(failures, 0);
  });

  test('metadata events supersede pending reads without changing session', () async {
    final pending = <Completer<http.Response>>[];
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((_) {
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      }),
    );
    connection.setToken('session');
    final revision = connection.sessionRevision;
    final old = connection.fetchTrackById('track');
    connection.invalidateMetadataReads();
    expect(connection.sessionRevision, revision);
    final fresh = connection.fetchTrackById('track');
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(2));
    pending.first.complete(
      http.Response(jsonEncode(offlineTestTrack(id: 'track', title: 'Before event').toJson()), 200),
    );
    expect((await old).title, 'Before event');
    final alsoFresh = connection.fetchTrackById('track');
    await Future<void>.delayed(Duration.zero);
    expect(pending, hasLength(2));
    pending.last.complete(http.Response(jsonEncode(offlineTestTrack(id: 'track', title: 'After event').toJson()), 200));
    expect((await fresh).title, 'After event');
    expect((await alsoFresh).title, 'After event');
  });
}

class _ControlledMetadataTransport extends ApiTransport {
  final List<Completer<Map<String, dynamic>>> requests = [];

  _ControlledMetadataTransport()
    : super(
        baseUrl: 'https://server.test/api',
        client: MockClient((_) async => throw StateError('Unexpected HTTP request')),
      );

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) {
    final request = Completer<Map<String, dynamic>>();

    requests.add(request);

    return request.future;
  }
}

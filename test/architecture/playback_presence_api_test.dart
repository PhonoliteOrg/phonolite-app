import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('presence capability requires advertisement and accepts the boolean wire value', () {
    expect(ServerCapabilities.fromJson({}).playbackPresence, isFalse);
    expect(ServerCapabilities.fromJson({'playback_presence': true}).playbackPresence, isTrue);
  });

  test(
    'presence binds the authenticated origin and token, disables redirects, and sends only ephemeral state',
    () async {
      final client = _Client((request) async => http.StreamedResponse(const Stream.empty(), 200));
      final connection = ServerConnection(baseUrl: 'https://music.test/api', client: client)..setToken('first-token');
      final send = connection.createPlaybackPresenceSender();
      connection.setBaseUrl('https://other.test/api');
      connection.setToken('second-token');
      await send('runtime-device', 7, true);
      final request = client.requests.single as http.Request;
      expect(request.url.toString(), 'https://music.test/api/account/playback/presence');
      expect(request.headers['Authorization'], 'Bearer first-token');
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.body), {'client_id': 'runtime-device', 'sequence': 7, 'playing': true});
    },
  );

  test('presence errors never notify the transport recovery callback', () async {
    final client = _Client((request) async => throw const SocketException('offline'));
    final connection = ServerConnection(baseUrl: 'https://music.test/api', client: client)..setToken('token');
    var recoveryCalls = 0;
    connection.onTransportFailure = (_) => recoveryCalls++;
    await expectLater(connection.createPlaybackPresenceSender()('device', 1, true), throwsA(isA<SocketException>()));
    expect(recoveryCalls, 0);
  });

  test('presence requests abort at their deadline including a stalled response body', () async {
    final body = StreamController<List<int>>();
    final client = _Client((request) async {
      unawaited((request as http.Abortable).abortTrigger!.then((_) => body.close()));
      return http.StreamedResponse(body.stream, 200);
    });
    final connection = ServerConnection(baseUrl: 'https://music.test/api', client: client)..setToken('token');
    final send = connection.createPlaybackPresenceSender(timeout: const Duration(milliseconds: 10));
    await expectLater(send('device', 1, true), throwsA(isA<RequestTimeoutException>()));
    await (client.requests.single as http.Abortable).abortTrigger;
    expect(body.isClosed, isTrue);
  });
}

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  _Client(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/api/session_management_api.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

void main() {
  test('account session mutations use authenticated POST and acknowledged counts', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer account-token');
      expect(jsonDecode(request.body), isEmpty);
      paths.add(request.url.path);

      return http.Response('{"revoked":3}', 200);
    });
    final transport = ApiTransport(baseUrl: 'https://music.test/api', client: client)..setToken('account-token');
    final api = SessionManagementApi(transport);

    expect(await api.revokeOtherSessions(), 3);
    expect(await api.revokeAllSessions(), 3);
    expect(paths, ['/api/account/sessions/revoke-others', '/api/account/sessions/revoke-all']);
    transport.close();
    client.close();
  });

  test('malformed or negative counts cannot be reported as success', () async {
    for (final payload in ['{}', '{"revoked":-1}', '{"revoked":1.5}', '{"revoked":"2"}']) {
      final client = MockClient((_) async => http.Response(payload, 200));
      final transport = ApiTransport(baseUrl: 'https://music.test/api', client: client);
      final api = SessionManagementApi(transport);

      await expectLater(api.revokeOtherSessions(), throwsFormatException);
      transport.close();
      client.close();
    }
  });

  test('failed mutations are never automatically retried', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;

      return http.Response('unavailable', 503);
    });
    final transport = ApiTransport(baseUrl: 'https://music.test/api', client: client);

    await expectLater(SessionManagementApi(transport).revokeAllSessions(), throwsA(isA<ApiException>()));
    expect(calls, 1);
    transport.close();
    client.close();
  });

  test('a response for a replaced session cannot acknowledge the new account', () async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    final transport = ApiTransport(baseUrl: 'https://music.test/api', client: client)..setToken('first-token');
    final result = SessionManagementApi(transport).revokeOtherSessions();
    transport.setToken('different-token');
    response.complete(http.Response('{"revoked":1}', 200));

    await expectLater(result, throwsA(isA<StateError>()));
    transport.close();
    client.close();
  });
}

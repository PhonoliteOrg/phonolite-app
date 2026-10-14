import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/entities/server_trust.dart';

import '../support/auth_test_helpers.dart';

void main() {
  const currentPassword = 'private old passphrase';
  const newPassword = '  my new password 🔒  ';
  var nextOrigin = 0;

  ServerConnection connectionFor(
    Future<http.Response> Function(http.Request) handler, {
    bool pinned = true,
    bool authenticated = true,
    String? baseUrl,
  }) {
    final client = MockClient(handler);
    addTearDown(client.close);
    final connection = ServerConnection(
      baseUrl: baseUrl ?? 'https://password-${nextOrigin++}.test/api/v1',
      client: client,
    );
    if (pinned) connection.setTrust(testServerTrust);
    if (authenticated) connection.setToken('original-token');
    return connection;
  }

  test(
    'password change uses authenticated pinned JSON without redirects',
    () async {
      var calls = 0;
      final connection = connectionFor((request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/password');
        expect(request.url.hasQuery, isFalse);
        expect(request.headers['Authorization'], 'Bearer original-token');
        expect(request.headers['Content-Type'], contains('application/json'));
        expect(request.headers['Cache-Control'], 'no-store');
        expect(request.followRedirects, isFalse);
        expect(jsonDecode(request.body), {
          'current_password': currentPassword,
          'new_password': newPassword,
        });
        return http.Response('', 204);
      });
      expect(connection.canChangeOwnPassword, isTrue);
      await connection.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      expect(calls, 1);
    },
  );

  test(
    'injected clients do not bypass password-change transport trust',
    () async {
      var calls = 0;
      for (final connection in [
        connectionFor((_) async {
          calls++;
          return http.Response('', 204);
        }, pinned: false),
        connectionFor((_) async {
          calls++;
          return http.Response('', 204);
        }, authenticated: false),
        connectionFor(
          (_) async {
            calls++;
            return http.Response('', 204);
          },
          pinned: false,
          baseUrl: 'http://password-http.test/api/v1',
        ),
        connectionFor((_) async {
          calls++;
          return http.Response('', 204);
        }, baseUrl: 'https://password-path.test/unexpected'),
        connectionFor((_) async {
          calls++;
          return http.Response('', 204);
        }, baseUrl: 'https://password-query.test/api/v1?token=secret'),
      ]) {
        expect(connection.canChangeOwnPassword, isFalse);
        await expectLater(
          connection.changeOwnPassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ),
          throwsA(isA<PasswordChangeException>()),
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'password validation allows short passwords and bounds UTF-8 bytes',
    () async {
      var calls = 0;
      final connection = connectionFor((_) async {
        calls++;
        return http.Response('', 204);
      });
      for (final values in [
        (current: '', next: newPassword),
        (current: 'a' * 1025, next: newPassword),
        (current: currentPassword, next: ''),
        (current: currentPassword, next: '🔒' * 257),
      ]) {
        await expectLater(
          connection.changeOwnPassword(
            currentPassword: values.current,
            newPassword: values.next,
          ),
          throwsA(isA<PasswordChangeException>()),
        );
      }
      expect(calls, 0);
      for (final password in [
        'x',
        '🔒',
        'x' * 1024,
        '🔒' * 256,
        currentPassword,
      ]) {
        await connection.changeOwnPassword(
          currentPassword: currentPassword,
          newPassword: password,
        );
      }
      expect(calls, 5);
    },
  );

  for (final status in [400, 401, 403, 429, 500, 302, 200]) {
    test(
      'status $status is safe and never retries or exposes its body',
      () async {
        var calls = 0;
        final connection = connectionFor((_) async {
          calls++;
          return http.Response(
            '$currentPassword $newPassword original-token raw-server-error',
            status,
            headers: {
              'location': 'https://attacker.test',
              'content-type': 'text/plain; charset=utf-8',
            },
          );
        });
        await expectLater(
          connection.changeOwnPassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ),
          throwsA(
            isA<PasswordChangeException>()
                .having((error) => error.statusCode, 'status code', status)
                .having(
                  (error) => error.requiresSignIn,
                  'requires sign in',
                  status == 401,
                )
                .having(
                  (error) => error.toString(),
                  'safe message',
                  allOf(
                    isNot(contains(currentPassword)),
                    isNot(contains(newPassword)),
                    isNot(contains('original-token')),
                    isNot(contains('raw-server-error')),
                  ),
                ),
          ),
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'a timeout preserves the current session without an automatic retry',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final connection = connectionFor((_) {
        calls++;
        return response.future;
      });
      await expectLater(
        connection.changeOwnPassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(
          isA<PasswordChangeException>().having(
            (error) => error.requiresSignIn,
            'requires sign in',
            isFalse,
          ),
        ),
      );
      expect(calls, 1);
      expect(connection.token, 'original-token');
      response.complete(http.Response('', 204));
    },
  );

  for (final change in ['token', 'origin', 'revision', 'pin']) {
    test('a changed $change cannot complete for a different session', () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final connection = connectionFor((_) {
        started.complete();
        return response.future;
      });
      final pending = connection.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      await started.future;
      switch (change) {
        case 'token':
          connection.setToken('new-token');
        case 'origin':
          connection.setBaseUrl('https://new-password-origin.test/api/v1');
        case 'revision':
          connection.setToken('different-token');
          connection.setToken('original-token');
        case 'pin':
          connection.setTrust(
            ServerTrust(spki: 'cd' * 32, opaqueKey: 'different-key'),
          );
      }
      response.complete(http.Response('', 204));
      await expectLater(pending, throwsA(isA<PasswordChangeException>()));
      expect(
        connection.token,
        change == 'origin'
            ? null
            : change == 'token'
            ? 'new-token'
            : 'original-token',
      );
    });
  }
}

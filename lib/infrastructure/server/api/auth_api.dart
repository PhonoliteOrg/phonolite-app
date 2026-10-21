import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class AuthApi {
  final ApiTransport _transport;

  AuthApi(this._transport);

  Future<String> login({required String username, required String password}) async {
    final url = _transport.baseUrl;
    final uri = Uri.parse(url);

    if (uri.scheme != 'https' || uri.path != '/api' || uri.userInfo.isNotEmpty) {
      throw StateError('HTTPS /api is required');
    }

    _transport.setToken(null);

    final revision = _transport.sessionRevision;
    final existing = _transport.trust ?? await ServerTrustStore.read(url);

    final response = await authenticateServer(
      host: uri.host,
      port: uri.port,
      username: username,
      password: password,
      expectedSpki: existing?.spki,
      expectedOpaque: existing?.opaqueKey,
    );

    if (_transport.baseUrl != url || _transport.sessionRevision != revision) {
      throw StateError('Sign-in cancelled');
    }

    final authenticated = ServerTrust(
      spki: response['spki_sha256'] as String,
      opaqueKey: response['opaque_key'] as String,
    );

    await ServerTrustStore.write(url, authenticated);

    if (_transport.baseUrl != url || _transport.sessionRevision != revision) {
      throw StateError('Sign-in cancelled');
    }

    _transport.setTrust(authenticated);

    final token = response['token'] as String?;

    if (token == null || token.isEmpty) {
      throw Exception('Missing token in login response');
    }

    _transport.setToken(token);

    return token;
  }

  Future<void> logout({Duration timeout = ApiTransport.defaultRequestTimeout}) async {
    await _transport.postVoid('/auth/logout', {}, timeout: timeout);
  }

  /// Changes only the authenticated user's password over the pinned HTTPS
  /// connection. This mutation is never retried or redirected. The controller
  /// keeps the originating session signed in; other account sessions are revoked.
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) async {
    if (!_transport.canChangeOwnPassword) {
      throw PasswordChangeException.forReason(PasswordChangeFailure.notAuthenticated);
    }

    if (currentPassword.isEmpty || utf8.encode(currentPassword).length > 1024) {
      throw PasswordChangeException.forReason(PasswordChangeFailure.invalidCurrentPassword);
    }

    if (newPassword.isEmpty) {
      throw PasswordChangeException.forReason(PasswordChangeFailure.missingNewPassword);
    }

    if (utf8.encode(newPassword).length > 1024) {
      throw PasswordChangeException.forReason(PasswordChangeFailure.newPasswordTooLong);
    }

    final url = _transport.baseUrl;
    final token = _transport.token;
    final revision = _transport.sessionRevision;
    final pin = _transport.trust!;

    bool sessionIsCurrent() =>
        _transport.baseUrl == url &&
        _transport.token == token &&
        _transport.sessionRevision == revision &&
        _transport.trust?.spki == pin.spki &&
        _transport.trust?.opaqueKey == pin.opaqueKey;

    final request = http.Request('POST', Uri.parse('$url/auth/password'));
    request.followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    });
    request.body = jsonEncode({'current_password': currentPassword, 'new_password': newPassword});

    late final http.StreamedResponse response;

    try {
      response = await _transport.client.send(request).timeout(timeout);
    } catch (_) {
      if (!sessionIsCurrent()) {
        throw PasswordChangeException.forReason(PasswordChangeFailure.sessionChanged);
      }

      // The server may have committed the change before the response was lost.
      // Do not retry or log the raw transport error. The server preserves this
      // session even if the change committed before the response was lost.
      throw PasswordChangeException.forReason(PasswordChangeFailure.unconfirmed);
    }

    // No endpoint response data is needed, even when the server returns an
    // error. Cancel rather than retaining or displaying an arbitrary body.
    unawaited(response.stream.listen((_) {}, onError: (Object _) {}).cancel().catchError((Object _) {}));

    if (!sessionIsCurrent()) {
      throw PasswordChangeException.forReason(PasswordChangeFailure.sessionChanged);
    }

    if (response.statusCode == 204) {
      return;
    }

    final reason = switch (response.statusCode) {
      400 => PasswordChangeFailure.rejected,
      401 => PasswordChangeFailure.sessionExpired,
      403 => PasswordChangeFailure.incorrectCurrentPassword,
      429 => PasswordChangeFailure.rateLimited,
      _ => PasswordChangeFailure.unconfirmed,
    };

    throw PasswordChangeException.forReason(
      reason,
      statusCode: response.statusCode,
      requiresSignIn: response.statusCode == 401,
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart' show ServerTrustRegistry, pinnedApiClient;
import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';

class ApiTransport {
  static const ApiResponseDecoder _responses = ApiResponseDecoder();
  static const int artistsPageSize = 60;
  static const Duration defaultRequestTimeout = Duration(seconds: 8);
  static const Duration healthRequestTimeout = Duration(seconds: 2);
  static const Duration slowRequestThreshold = Duration(milliseconds: 1200);
  static const int maxGetAttempts = 3;

  String _baseUrl;
  late final http.Client client;
  final bool injectedClient;
  final ServerReachabilityProbe serverProbe;
  final Random retryJitter = Random();
  final Map<String, Future<Map<String, dynamic>>> _metadataRequests = {};
  int _sessionRevision = 0;
  String? _token;
  void Function(Object error)? onTransportFailure;

  ApiTransport({required String baseUrl, http.Client? client, ServerReachabilityProbe? serverProbe})
    : _baseUrl = ApiTransport.sanitizeBaseUrl(baseUrl),
      serverProbe = serverProbe ?? probeServerConnection,
      injectedClient = client != null {
    this.client = client ?? pinnedApiClient(() => _baseUrl);
  }

  String get baseUrl => _baseUrl;

  String? get token => _token;

  ServerTrust? get trust => ServerTrustRegistry.lookup(_baseUrl);

  bool get hasTrustedTransport => injectedClient || trust != null;

  int get sessionRevision => _sessionRevision;

  bool get canChangeOwnPassword {
    final uri = Uri.tryParse(_baseUrl);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.path != '/api' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }

    final authenticatedTrust = trust;

    return _token?.isNotEmpty == true &&
        authenticatedTrust != null &&
        ServerTrust.fromJson(authenticatedTrust.toJson()) != null;
  }

  /// A fresh header map; callers cannot mutate connection authentication state.
  Map<String, String> get authorizationHeaders => {
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  void setTrust(ServerTrust value) => ServerTrustRegistry.register(_baseUrl, value);

  void setBaseUrl(String baseUrl) {
    final sanitized = ApiTransport.sanitizeBaseUrl(baseUrl);

    if (_baseUrl == sanitized) {
      return;
    }

    _baseUrl = sanitized;
    _token = null;
    invalidateMetadataRequests();
  }

  Future<String> resolveBaseUrl(String input) async {
    final trimmed = ApiTransport.sanitizeBaseUrl(input);

    if (trimmed.isEmpty) {
      throw ServerConnectionCheckException.forReason(ServerConnectionFailure.missingAddress);
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/' && uri.path != '/api')) {
      throw ServerConnectionCheckException.forReason(ServerConnectionFailure.invalidAddress);
    }

    return ensureApiBase(candidate);
  }

  /// Verify the entered endpoint without changing the session or trusting a new
  /// identity. A remembered certificate pin is enforced even before sign-in.
  Future<void> verifyServerConnection(String input, {Duration timeout = const Duration(seconds: 10)}) async {
    final resolved = await resolveBaseUrl(input);
    final uri = Uri.parse(resolved);

    try {
      Future<void> probeServer() async {
        final existing = ServerTrustRegistry.lookup(resolved) ?? await ServerTrustStore.read(resolved);

        await serverProbe(host: uri.host, port: uri.port, expectedSpki: existing?.spki);
      }

      await probeServer().timeout(timeout);
    } on TimeoutException {
      throw ServerConnectionCheckException.forReason(ServerConnectionFailure.timedOut);
    } on ServerIdentityChangedException {
      throw ServerConnectionCheckException.forReason(ServerConnectionFailure.identityChanged);
    } on QuicException catch (error) {
      throw ServerConnectionCheckException.forReason(ServerConnectionFailure.connectionFailed, detail: error.message);
    }
  }

  /// Public, credential-free detection only. This never replaces remembered trust.
  Future<bool> hasServerIdentityChanged() async {
    if (trust == null || injectedClient) return false;
    try {
      await verifyServerConnection(_baseUrl);
    } on ServerConnectionCheckException catch (error) {
      return error.reason == ServerConnectionFailure.identityChanged;
    } catch (_) {}
    return false;
  }

  void setToken(String? token) {
    if (token != null && token.isNotEmpty && !hasTrustedTransport) {
      throw StateError('Authenticate the server before using a saved token');
    }

    if (_token == token) {
      return;
    }

    _token = token;
    invalidateMetadataRequests();
  }

  void invalidateMetadataRequests() {
    _sessionRevision++;
    invalidateMetadataReads();
  }

  /// A metadata event supersedes reads that began before that update, without
  /// changing the authenticated session or cancelling unrelated repair work.
  void invalidateMetadataReads() {
    _metadataRequests.clear();
  }

  String ensureApiBase(String url) {
    final uri = Uri.parse(url);
    var path = uri.path;

    if (path.isEmpty || path == '/') {
      path = '/api';
    } else if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    if (!path.endsWith('/api')) {
      path = '$path/api';
    }

    return uri.replace(path: path, query: null).toString();
  }

  String ensureRoot(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    var path = uri.path;

    if (path.endsWith('/api')) {
      path = path.substring(0, path.length - '/api'.length);

      if (path.isEmpty) {
        path = '/';
      }
    }

    return uri.replace(path: path, query: null).toString();
  }

  static String sanitizeInput(String input) {
    var value = input.trim();

    while (value.endsWith('?') || value.endsWith('#')) {
      value = value.substring(0, value.length - 1);
    }

    return value;
  }

  static String sanitizeBaseUrl(String input) {
    final cleaned = ApiTransport.sanitizeInput(input);

    return cleaned.replaceAll(RegExp(r'/+$'), '');
  }

  static String encodePathSegment(String value) {
    return Uri.encodeComponent(value);
  }

  Future<int?> probeHealthMs(String url, {required Duration timeout}) async {
    final stopwatch = Stopwatch();
    stopwatch.start();

    try {
      final response = await client.get(buildHealthUrl(url)).timeout(timeout);

      final success = response.statusCode >= 200 && response.statusCode < 300;

      return success ? stopwatch.elapsedMilliseconds : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) async {
    for (final url in healthProbeBaseUrls(_baseUrl)) {
      final elapsedMs = await probeHealthMs(url, timeout: timeout);
      if (elapsedMs != null) {
        return elapsedMs;
      }
    }

    return null;
  }

  Iterable<String> healthProbeBaseUrls(String baseUrl) sync* {
    final rootUrl = ensureRoot(baseUrl);

    yield rootUrl;

    if (rootUrl != baseUrl) {
      yield baseUrl;
    }
  }

  Uri buildHealthUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');

    return uri.replace(path: path.isEmpty ? '/health' : '$path/health', query: null);
  }

  Future<Map<String, dynamic>> getMetadata(String path) {
    final existing = _metadataRequests[path];
    if (existing != null) {
      return existing;
    }

    late final Future<Map<String, dynamic>> pending;

    void removePending() {
      if (identical(_metadataRequests[path], pending)) {
        _metadataRequests.remove(path);
      }
    }

    pending = get(path).whenComplete(removePending);
    _metadataRequests[path] = pending;

    return pending;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Duration timeout = defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _get(path, timeout: timeout, retryable: retryable);

    return decode(response);
  }

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Duration timeout = defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _get(path, timeout: timeout, retryable: retryable);

    return _responses.list(response, path: path);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload) async {
    final response = await _post(path, payload);

    return decode(response);
  }

  Future<List<Map<String, dynamic>>> postList(String path, Map<String, dynamic> payload) async {
    final response = await _post(path, payload);

    return _responses.list(response, path: path);
  }

  Future<void> postVoid(String path, Map<String, dynamic> payload, {Duration timeout = defaultRequestTimeout}) async {
    final response = await _post(path, payload, timeout: timeout);

    _responses.requireSuccess(response);
  }

  Future<void> delete(String path) async {
    final response = await executeRequest(
      () => client.delete(Uri.parse('$_baseUrl$path'), headers: buildHeaders()),
      label: 'DELETE $path',
    );

    _responses.requireSuccess(response);
  }

  Map<String, String> buildHeaders({bool contentType = false, String? contentTypeValue}) {
    final headers = authorizationHeaders;

    if (contentTypeValue != null && contentTypeValue.isNotEmpty) {
      headers['Content-Type'] = contentTypeValue;
    } else if (contentType) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  Future<http.Response> executeRequest(
    Future<http.Response> Function() request, {
    bool retryable = false,
    Duration timeout = defaultRequestTimeout,
    String label = 'request',
  }) async {
    final safeLabel = _safeRequestLabel(label);
    final maxAttempts = retryable ? ApiTransport.maxGetAttempts : 1;
    Object? lastError;
    StackTrace? lastStackTrace;

    final stopwatch = Stopwatch();
    stopwatch.start();

    Future<void> backoff(int attempt) => Future<void>.delayed(retryDelay(attempt));

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await request().timeout(timeout);

        final retryableStatus = response.statusCode >= 500 && response.statusCode < 600;

        if (retryable && retryableStatus && attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt failed with ${response.statusCode}; retrying after ${stopwatch.elapsedMilliseconds}ms',
            name: 'ServerConnection',
          );

          await backoff(attempt);
          continue;
        }

        if (attempt > 1 || stopwatch.elapsed >= ApiTransport.slowRequestThreshold) {
          developer.log(
            '$safeLabel completed in ${stopwatch.elapsedMilliseconds}ms after $attempt attempt(s) with ${response.statusCode}',
            name: 'ServerConnection',
          );
        }

        return response;
      } on TimeoutException catch (_, stackTrace) {
        lastError = RequestTimeoutException(timeout);
        lastStackTrace = stackTrace;

        if (attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt timed out after ${timeout.inMilliseconds}ms; retrying',
            name: 'ServerConnection',
          );

          await backoff(attempt);
          continue;
        }
      } on SocketException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;

        if (retryable && attempt < maxAttempts) {
          developer.log('$safeLabel attempt $attempt hit socket error; retrying', name: 'ServerConnection');

          await backoff(attempt);
          continue;
        }
      } on http.ClientException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;

        if (retryable && attempt < maxAttempts) {
          developer.log('$safeLabel attempt $attempt hit client error; retrying', name: 'ServerConnection');

          await backoff(attempt);
          continue;
        }
      }
    }

    if (lastError != null && lastStackTrace != null) {
      try {
        onTransportFailure?.call(lastError);
      } catch (_) {}

      developer.log(
        '$safeLabel failed after ${stopwatch.elapsedMilliseconds}ms',
        name: 'ServerConnection',
        error: lastError,
        stackTrace: lastStackTrace,
      );

      Error.throwWithStackTrace(lastError, lastStackTrace);
    }

    throw RequestTimeoutException(timeout);
  }

  Duration retryDelay(int attempt) {
    final baseMs = attempt == 1 ? 300 : 900;

    return Duration(milliseconds: baseMs + retryJitter.nextInt(250));
  }

  Future<Map<String, dynamic>> decode(http.Response response) => _responses.object(response);

  Future<http.Response> _get(String path, {required Duration timeout, required bool retryable}) {
    // All retried JSON reads keep the server and credentials that started them.
    final uri = Uri.parse('$_baseUrl$path');
    final headers = buildHeaders();

    return executeRequest(
      () => client.get(uri, headers: headers),
      label: 'GET $path',
      retryable: retryable,
      timeout: timeout,
    );
  }

  Future<http.Response> _post(String path, Map<String, dynamic> payload, {Duration timeout = defaultRequestTimeout}) {
    final body = jsonEncode(payload);

    return executeRequest(
      () => client.post(Uri.parse('$_baseUrl$path'), headers: buildHeaders(contentType: true), body: body),
      label: 'POST $path',
      timeout: timeout,
    );
  }
}

/// Keep only route templates. Never persist query values, resource IDs,
/// credentials, or a configured server address in request logs.
String _safeRequestLabel(String label) {
  if (label == 'GET artwork' || label == 'PUT playlist cover' || label == 'DELETE playlist cover') {
    return label;
  }

  final separator = label.indexOf(' ');

  if (separator < 0) {
    return 'request';
  }

  final method = label.substring(0, separator);

  if (!const ['GET', 'POST', 'PUT', 'DELETE'].contains(method)) {
    return 'request';
  }

  final path = label.substring(separator + 1).split('?').first;
  const staticRoutes = {
    '/auth/opaque/start',
    '/auth/opaque/finish',
    '/auth/logout',
    '/browse/artists',
    '/browse/likes',
    '/library/playlists',
    '/library/shuffle',
    '/library/search',
    '/library/match-tracks',
    '/library/likes/batch',
    '/stats',
    '/download/batches',
    '/download/jobs',
    '/server/capabilities',
    '/server/ports',
    '/player/settings',
  };

  if (staticRoutes.contains(path)) {
    return '$method $path';
  }

  const dynamicRoutes = {
    '/browse/artists/:id/albums',
    '/browse/artists/:id/releases',
    '/browse/artists/:id',
    '/browse/albums/:id/tracks',
    '/browse/playlists/:id/tracks',
    '/browse/tracks/:id',
    '/library/albums/:id',
    '/library/tracks/:id/offline-metadata',
    '/library/likes/:id',
    '/library/playlists/:id',
    '/download/jobs/:id/actions',
  };

  for (final route in dynamicRoutes) {
    final pattern = RegExp('^${route.replaceAll(':id', '[^/]+')}\$');

    if (pattern.hasMatch(path)) {
      return '$method $route';
    }
  }

  return '$method /unknown';
}

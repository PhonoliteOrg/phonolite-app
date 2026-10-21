import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/auth/server_trust.dart';

export 'package:phonolite_app/data/storage/auth/server_trust_store.dart';

/// Per-isolate trust registry. Worker isolates explicitly receive authenticated
/// pins; no system CA can override a Phonolite pin.
class ServerTrustRegistry {
  static final Map<String, ServerTrust> _pins = {};
  static int _generation = 0;

  static String origin(Uri uri) => ServerTrust.origin(uri);

  static void register(String baseUrl, ServerTrust trust) {
    final uri = Uri.parse(baseUrl);

    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('HTTPS is required');
    }

    final key = origin(uri);
    final previous = _pins[key];
    _pins[key] = trust;
    if (previous != null && (previous.spki != trust.spki || previous.opaqueKey != trust.opaqueKey)) {
      _generation++;
    }
  }

  static ServerTrust? lookup(String baseUrl) => _pins[origin(Uri.parse(baseUrl))];

  static void forget(String baseUrl) {
    if (_pins.remove(origin(Uri.parse(baseUrl))) != null) {
      _generation++;
    }
  }

  static void validate(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || !_pins.containsKey(origin(uri))) {
      throw HandshakeException('Sign in to authenticate this server first');
    }
  }

  static bool accepts(X509Certificate certificate, String host, int port) {
    final trust = _pins[origin(Uri(scheme: 'https', host: host, port: port))];
    if (trust == null) {
      return false;
    }

    final now = DateTime.now();

    if (now.isBefore(certificate.startValidity) || now.isAfter(certificate.endValidity)) {
      return false;
    }

    try {
      return certificateSpki(certificate.der) == trust.spki;
    } catch (_) {
      return false;
    }
  }
}

void installServerTrustOverrides({HttpClient Function(SecurityContext)? createHttpClient}) {
  HttpOverrides.global = _PinnedOverrides(createHttpClient);
}

http.Client pinnedApiClient(String Function() baseUrl, {HttpClient Function(SecurityContext)? createHttpClient}) =>
    _PinnedApiClient(baseUrl, createHttpClient);

class _PinnedOverrides extends HttpOverrides {
  final HttpClient Function(SecurityContext)? _createHttpClient;

  _PinnedOverrides([this._createHttpClient]);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _PinnedHttpClient(() {
      final securityContext = SecurityContext(withTrustedRoots: false);
      final client = _createHttpClient?.call(securityContext) ?? super.createHttpClient(securityContext);

      client.badCertificateCallback = ServerTrustRegistry.accepts;
      client.findProxy = (_) => 'DIRECT';

      return client;
    });
  }
}

class _PinnedApiClient extends http.BaseClient {
  final String Function() baseUrl;
  final http.Client _inner;

  _PinnedApiClient(this.baseUrl, HttpClient Function(SecurityContext)? createHttpClient)
    : _inner = IOClient(_PinnedOverrides(createHttpClient).createHttpClient(null));

  @override
  void close() => _inner.close();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (ServerTrustRegistry.origin(request.url) != ServerTrustRegistry.origin(Uri.parse(baseUrl()))) {
      throw StateError('Cross-server request blocked');
    }

    ServerTrustRegistry.validate(request.url);
    request.followRedirects = false;

    return _inner.send(request);
  }
}

/// Used by Flutter NetworkImage as well as direct download clients. All request
/// entry points require a pinned HTTPS origin and turn off automatic redirects.
class _PinnedHttpClient implements HttpClient {
  final HttpClient Function() _createClient;
  HttpClient inner;
  int _generation = ServerTrustRegistry._generation;
  bool _closed = false;

  _PinnedHttpClient(this._createClient) : inner = _createClient();

  void _refreshTrust() {
    if (_generation == ServerTrustRegistry._generation || _closed) {
      return;
    }

    final previous = inner;
    // A pooled TLS connection does not re-run badCertificateCallback. Retire
    // every old pool before another request can use a replaced or forgotten pin.
    previous.close(force: true);
    inner = _createClient()
      ..idleTimeout = previous.idleTimeout
      ..connectionTimeout = previous.connectionTimeout
      ..maxConnectionsPerHost = previous.maxConnectionsPerHost
      ..autoUncompress = previous.autoUncompress
      ..userAgent = previous.userAgent;
    _generation = ServerTrustRegistry._generation;
  }

  @override
  Duration get idleTimeout => inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => inner.autoUncompress;

  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;

  @override
  String? get userAgent => inner.userAgent;

  @override
  set userAgent(String? value) => inner.userAgent = value;

  @override
  void close({bool force = false}) {
    _closed = true;
    inner.close(force: force);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (_closed) {
      throw HttpException('HTTP client is closed', uri: url);
    }
    _refreshTrust();
    ServerTrustRegistry.validate(url);
    final generation = _generation;
    final request = await inner.openUrl(method, url);
    if (generation != ServerTrustRegistry._generation) {
      _refreshTrust();
      final error = HandshakeException('Server trust changed during the request');
      request.abort(error);
      throw error;
    }

    request.followRedirects = false;

    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      openUrl(method, Uri(scheme: 'https', host: host, port: port).resolve(path));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => open('GET', host, port, path);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => open('POST', host, port, path);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => open('PUT', host, port, path);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => open('DELETE', host, port, path);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => open('PATCH', host, port, path);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => open('HEAD', host, port, path);

  // Unsupported authentication/proxy/key-log overrides fail closed.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Pinned transport: ${invocation.memberName}');
}

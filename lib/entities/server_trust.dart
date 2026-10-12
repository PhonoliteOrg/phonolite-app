import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:phonolite_quic/phonolite_quic.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerTrustStore {
  static const _vault = FlutterSecureStorage();
  static String _key(String url) =>
      'phonolite.trust.v1.${base64Url.encode(utf8.encode(ServerTrustRegistry.origin(Uri.parse(url))))}';
  static Future<ServerTrust?> read(String url) async {
    final raw = await _vault.read(key: _key(url));
    return raw == null ? null : ServerTrust.fromJson(jsonDecode(raw));
  }

  static Future<void> write(String url, ServerTrust trust) =>
      _vault.write(key: _key(url), value: jsonEncode(trust.toJson()));
}

class ServerTrust {
  const ServerTrust({required this.spki, required this.opaqueKey});
  final String spki;
  final String opaqueKey;
  Map<String, String> toJson() => {'spki': spki, 'opaqueKey': opaqueKey};
  static ServerTrust? fromJson(dynamic value) {
    if (value is! Map) return null;
    final spki = value['spki']?.toString() ?? '';
    final opaque = value['opaqueKey']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(spki) || opaque.isEmpty) {
      return null;
    }
    return ServerTrust(spki: spki, opaqueKey: opaque);
  }
}

/// Per-isolate trust registry. Worker isolates explicitly receive authenticated
/// pins; no system CA can override a Phonolite pin.
class ServerTrustRegistry {
  static final Map<String, ServerTrust> _pins = {};
  static String origin(Uri uri) =>
      '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
  static void register(String baseUrl, ServerTrust trust) {
    final uri = Uri.parse(baseUrl);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('HTTPS is required');
    }
    _pins[origin(uri)] = trust;
  }

  static ServerTrust? lookup(String baseUrl) =>
      _pins[origin(Uri.parse(baseUrl))];
  static void validate(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_pins.containsKey(origin(uri))) {
      throw HandshakeException('Sign in to authenticate this server first');
    }
  }

  static bool accepts(X509Certificate certificate, String host, int port) {
    final trust = _pins[origin(Uri(scheme: 'https', host: host, port: port))];
    if (trust == null) return false;
    final now = DateTime.now();
    if (now.isBefore(certificate.startValidity) ||
        now.isAfter(certificate.endValidity)) {
      return false;
    }
    try {
      return certificateSpki(certificate.der) == trust.spki;
    } catch (_) {
      return false;
    }
  }
}

void installServerTrustOverrides() {
  HttpOverrides.global = _PinnedOverrides();
}

class _PinnedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(
      SecurityContext(withTrustedRoots: false),
    );
    client.badCertificateCallback = ServerTrustRegistry.accepts;
    client.findProxy = (_) => 'DIRECT';
    return _PinnedHttpClient(client);
  }
}

http.Client pinnedApiClient(String Function() baseUrl) =>
    _PinnedApiClient(baseUrl);

class _PinnedApiClient extends http.BaseClient {
  _PinnedApiClient(this.baseUrl)
    : _inner = IOClient(_PinnedOverrides().createHttpClient(null));
  final String Function() baseUrl;
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (ServerTrustRegistry.origin(request.url) !=
        ServerTrustRegistry.origin(Uri.parse(baseUrl()))) {
      throw StateError('Cross-server request blocked');
    }
    ServerTrustRegistry.validate(request.url);
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Used by Flutter NetworkImage as well as direct download clients. All request
/// entry points require a pinned HTTPS origin and turn off automatic redirects.
class _PinnedHttpClient implements HttpClient {
  _PinnedHttpClient(this.inner);
  final HttpClient inner;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    ServerTrustRegistry.validate(url);
    final request = await inner.openUrl(method, url);
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
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(
    method,
    Uri(scheme: 'https', host: host, port: port).resolve(path),
  );
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  void close({bool force = false}) => inner.close(force: force);
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
  // Unsupported authentication/proxy/key-log overrides fail closed.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Pinned transport: ${invocation.memberName}');
}

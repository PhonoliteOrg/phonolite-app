import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';

abstract interface class AppUpdateFeed {
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration);
  void close();
}

class HttpAppUpdateFeed implements AppUpdateFeed {
  static const _timeout = Duration(seconds: 10);
  static const _maximumBytes = 1024 * 1024;
  static const _redirectStatuses = {301, 302, 303, 307, 308};

  final http.Client Function() _createClient;
  http.Client? _activeClient;

  HttpAppUpdateFeed({http.Client Function()? createClient}) : _createClient = createClient ?? http.Client.new;

  @override
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration) async {
    final client = _createClient();
    _activeClient = client;
    try {
      final response = await _fetch(client, Uri.parse(configuration.feedUrl));
      if (response.statusCode != 200) {
        throw http.ClientException('Update feed returned HTTP ${response.statusCode}.');
      }
      final source = await _readBody(response).timeout(_timeout);
      return AppUpdateRelease.latestFromAppcast(source, currentVersion: configuration.currentVersion);
    } finally {
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      client.close();
    }
  }

  @override
  void close() {
    _activeClient?.close();
    _activeClient = null;
  }

  Future<http.StreamedResponse> _fetch(http.Client client, Uri uri) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        throw const FormatException('Update feeds and redirects must use HTTPS without credentials.');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Accept'] = 'application/rss+xml, application/xml, text/xml';
      final response = await client.send(request).timeout(_timeout);
      if (!_redirectStatuses.contains(response.statusCode)) {
        return response;
      }
      await response.stream.listen((_) {}).cancel();
      final location = response.headers['location'];
      if (location == null) {
        throw const FormatException('The update feed redirect has no destination.');
      }
      uri = uri.resolve(location);
    }
    throw const FormatException('The update feed redirected too many times.');
  }

  Future<String> _readBody(http.StreamedResponse response) async {
    if ((response.contentLength ?? 0) > _maximumBytes) {
      throw const FormatException('The update feed is too large.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maximumBytes) {
        throw const FormatException('The update feed is too large.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}

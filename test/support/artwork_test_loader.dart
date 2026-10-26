import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

/// Bridges the existing fake Flutter HTTP clients to the injected capability.
/// A missing fake fails locally; this helper never creates a real HTTP client.
class ArtworkTestLoader implements ArtworkLoader {
  final HttpClient? client;

  const ArtworkTestLoader({this.client});

  @override
  String get cacheScope => 'test-artwork';

  @override
  Future<void> close() async {}

  @override
  Future<void> invalidate(ArtworkRequest request) async {}

  @override
  Future<T> decode<T>(String scope, Future<T> Function() operation) => operation();

  @override
  Future<Uint8List> load(ArtworkRequest request) async {
    final http = client ?? debugNetworkImageHttpClientProvider?.call();

    if (http == null) {
      throw const ArtworkLoadException(statusCode: 404);
    }

    final pending = await http.getUrl(Uri.parse(request.source));
    request.headers.forEach(pending.headers.add);
    final response = await pending.close();

    if (response.statusCode != 200) {
      throw ArtworkLoadException(statusCode: response.statusCode);
    }

    final bytes = BytesBuilder(copy: false);

    await for (final chunk in response) {
      bytes.add(chunk);
    }

    return bytes.takeBytes();
  }
}

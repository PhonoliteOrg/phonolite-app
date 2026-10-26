import 'dart:typed_data';

/// Immutable input to the shared artwork loader. Headers are never persisted.
class ArtworkRequest {
  final String source;
  final Map<String, String> headers;
  final int? decodeSize;

  ArtworkRequest({required this.source, Map<String, String> headers = const {}, this.decodeSize})
    : headers = Map.unmodifiable(headers);
}

/// A borrowed loading capability. The application composition owns shutdown.
/// [cacheScope] changes when authenticated identity changes, preventing stale
/// decoded images from being reused by another session.
abstract interface class ArtworkLoader {
  String get cacheScope;

  Future<Uint8List> load(ArtworkRequest request);

  /// Admits the complete load-and-codec operation before its bytes allocate.
  /// Waiting callbacks stay lightweight; a changed identity rejects old work.
  Future<T> decode<T>(String scope, Future<T> Function() operation);

  Future<void> invalidate(ArtworkRequest request);

  Future<void> close();
}

class ArtworkLoadException implements Exception {
  final int? statusCode;
  final Duration? retryAfter;

  const ArtworkLoadException({this.statusCode, this.retryAfter});

  @override
  String toString() => 'Artwork loading failed${statusCode == null ? '' : ' ($statusCode)'}';
}

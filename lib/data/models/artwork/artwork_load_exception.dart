class ArtworkLoadException implements Exception {
  final int? statusCode;
  final Duration? retryAfter;

  const ArtworkLoadException({this.statusCode, this.retryAfter});

  @override
  String toString() => 'Artwork loading failed${statusCode == null ? '' : ' ($statusCode)'}';
}

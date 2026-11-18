/// Immutable input to the shared artwork loader.
class ArtworkRequest {
  final String source;
  final int? sessionRevision;
  final int? decodeSize;

  const ArtworkRequest({required this.source, this.sessionRevision, this.decodeSize});

  /// Rounds a thumbnail's physical pixel size up to the server rendition sizes.
  ///
  /// Decoding at the bucket rather than the exact layout size keeps one cached
  /// image per artwork while a window resize changes card sizes every frame.
  static int thumbnailBucket(int pixels) => pixels <= 128
      ? 128
      : pixels <= 256
      ? 256
      : 512;
}

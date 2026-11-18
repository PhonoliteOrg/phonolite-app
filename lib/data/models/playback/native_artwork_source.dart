/// Identifies a cover in the native cache, including its authorization context.
class NativeArtworkSource {
  final String key;
  final String? url;
  final String? path;
  final int? sessionRevision;

  const NativeArtworkSource({required this.key, this.url, this.path, this.sessionRevision});
}

class StorageAccessRestoration {
  final Map<String, String> paths;
  final Set<String> unavailable;

  const StorageAccessRestoration({this.paths = const {}, this.unavailable = const {}});

  factory StorageAccessRestoration.fromPlatform(Map<Object?, Object?> values) => StorageAccessRestoration(
    paths: Map.unmodifiable((values['paths'] as Map? ?? const {}).cast<String, String>()),
    unavailable: Set.unmodifiable((values['unavailable'] as List? ?? const []).cast<String>()),
  );

  String? resolve(String? path) => paths[path] ?? path;
}

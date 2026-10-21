class ServerTrust {
  final String spki;
  final String opaqueKey;

  const ServerTrust({required this.spki, required this.opaqueKey});

  /// The identity scope shared by persisted pins and isolate trust registries.
  static String origin(Uri uri) => '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';

  static ServerTrust? fromJson(dynamic value) {
    if (value is! Map) {
      return null;
    }

    final spki = value['spki']?.toString() ?? '';
    final opaque = value['opaqueKey']?.toString() ?? '';

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(spki) || opaque.isEmpty) {
      return null;
    }

    return ServerTrust(spki: spki, opaqueKey: opaque);
  }

  Map<String, String> toJson() => {'spki': spki, 'opaqueKey': opaqueKey};
}

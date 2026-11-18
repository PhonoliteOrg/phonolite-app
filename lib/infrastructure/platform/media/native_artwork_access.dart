import 'package:phonolite_app/infrastructure/server/server_connection.dart';

/// Attaches credentials only as a remote artwork URL crosses the native channel.
class NativeArtworkAccess {
  final ServerConnection connection;
  const NativeArtworkAccess(this.connection);

  Map<String, String> fields(String? url, int? revision) {
    if (url == null || revision != connection.sessionRevision) return const {};
    final uri = Uri.tryParse(url);
    final pin = connection.trust?.spki;
    if (uri == null || pin == null || !connection.isArtworkOrigin(uri)) return const {};
    return {'serverPin': pin, if (connection.token case final token?) 'token': token};
  }
}

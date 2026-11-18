import 'package:phonolite_app/data/models/auth/server_trust.dart';

/// Account identity for in-memory consumers and existing account-scoped stores.
class SessionAccount {
  final String userId;
  final String? serverId;
  final String storageScope;

  SessionAccount({required this.userId, this.serverId, required String baseUrl, required ServerTrust? trust})
    : storageScope = _storageScope(baseUrl, trust, userId);

  static String _storageScope(String baseUrl, ServerTrust? trust, String userId) {
    final origin = ServerTrust.origin(Uri.parse(baseUrl));
    final identity = trust == null ? origin : '${trust.spki}/${trust.opaqueKey}';
    return '$origin/$identity/$userId';
  }

  String? get artworkScope => serverId == null ? null : '$serverId|$userId';
}

import 'package:phonolite_app/data/models/auth/session_revocation_result.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';

class SessionManagementApi extends JsonApiEndpoint {
  SessionManagementApi(super.transport);

  Future<int> revokeOtherSessions() => _revoke('/account/sessions/revoke-others');

  Future<int> revokeAllSessions() => _revoke('/account/sessions/revoke-all');

  Future<int> _revoke(String path) async {
    final revision = transport.sessionRevision;
    final result = await postValue(path, {}, SessionRevocationResult.fromJson);

    if (transport.sessionRevision != revision) {
      throw StateError('The signed-in account changed during the sign-out request.');
    }

    return result.revoked;
  }
}

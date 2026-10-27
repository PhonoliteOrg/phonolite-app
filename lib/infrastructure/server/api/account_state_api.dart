import 'package:phonolite_app/data/models/auth/account_state.dart';
import 'package:phonolite_app/data/models/playback/account_last_track.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/sse_transport.dart';

class AccountStateApi extends JsonApiEndpoint {
  late final SseTransport _events = SseTransport(transport);

  AccountStateApi(super.transport);

  Stream<RevisionEvent<AccountRevisions>> streamEvents() =>
      _events.openJson(path: '/account/events', decode: AccountState.eventFromJson);

  Future<AccountState> fetchState() => getValue('/account/state', AccountState.fromJson);

  Future<AccountLastTrack> fetchLastTrack() => getValue('/account/last-track', AccountLastTrack.fromJson);

  Future<AccountLastTrack> reportTrack({
    required String trackId,
    required String sessionId,
    required int sequence,
    required String requestId,
  }) => postValue('/account/last-track', {
    'track_id': trackId,
    'session_id': sessionId,
    'sequence': sequence,
    'request_id': requestId,
  }, AccountLastTrack.fromJson);
}

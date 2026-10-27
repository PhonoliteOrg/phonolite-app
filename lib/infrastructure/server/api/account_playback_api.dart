import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class AccountPlaybackApi extends JsonApiEndpoint {
  AccountPlaybackApi(super.transport);

  Future<AccountPlaybackSnapshot> fetch() => getValue('/account/playback', AccountPlaybackSnapshot.fromJson);

  Future<AccountPlaybackSnapshot> save({
    required int expectedRevision,
    required String sessionId,
    required int sequence,
    required String requestId,
    required String intent,
    required PlaybackResumeCheckpoint checkpoint,
    String? generation,
    String? clientId,
  }) => postValue('/account/playback', {
    'expected_revision': expectedRevision,
    'session_id': sessionId,
    'sequence': sequence,
    'request_id': requestId,
    'intent': intent,
    'checkpoint': checkpoint.toJson(),
    if (generation != null) 'generation': generation,
    if (clientId != null) 'client_id': clientId,
  }, AccountPlaybackSnapshot.fromJson);

  Future<ShuffleSessionPage> fetchDeck(String deckId, {int offset = 0, int limit = 10}) {
    final id = ApiTransport.encodePathSegment(deckId);

    return getValue('/account/playback/decks/$id?offset=$offset&limit=$limit', ShuffleSessionPage.fromJson);
  }

  Future<void> clear({required int expectedRevision}) =>
      transport.delete('/account/playback?expected_revision=$expectedRevision');
}

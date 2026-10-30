import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class AccountPlaybackApi extends JsonApiEndpoint {
  AccountPlaybackApi(super.transport);

  Future<AccountPlaybackSnapshot> fetch() => getValue('/account/playback', AccountPlaybackSnapshot.fromJson);

  /// Bind origin and authentication now so queued reports cannot use a later
  /// account's credentials. Presence failures never trigger audio recovery.
  Future<void> Function(String, int, bool) presenceSender({Duration timeout = const Duration(seconds: 3)}) {
    final uri = Uri.parse('${transport.baseUrl}/account/playback/presence');
    final headers = transport.buildHeaders(contentType: true);
    if (!transport.hasTrustedTransport || transport.token?.isNotEmpty != true) {
      throw StateError('Playback presence requires an authenticated server');
    }

    return (clientId, sequence, playing) async {
      final aborted = Completer<void>();
      final request = http.AbortableRequest('POST', uri, abortTrigger: aborted.future)
        ..followRedirects = false
        ..headers.addAll(headers)
        ..body = jsonEncode({'client_id': clientId, 'sequence': sequence, 'playing': playing});
      try {
        await (() async {
          final response = await transport.client.send(request);
          await response.stream.drain<void>();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw ApiException(response.statusCode, 'Playback presence rejected');
          }
        })().timeout(
          timeout,
          onTimeout: () {
            if (!aborted.isCompleted) aborted.complete();
            throw RequestTimeoutException(timeout);
          },
        );
      } finally {
        if (!aborted.isCompleted) aborted.complete();
      }
    };
  }

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

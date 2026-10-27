import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/collections/account_collection_event.dart';
import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/api/account_events_api.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

void main() {
  test('account frames share cancellable authenticated SSE framing', () async {
    http.BaseRequest? request;
    final api = _api((value) async {
      request = value;

      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(': keepalive\r\n\r\ndata: {"kind":"ready","revision":0}\r'),
          utf8.encode('\n\r\ndata: invalid\n\ndata: {"kind":"future","revision":1}\n\n'),
          utf8.encode('data: {"kind":"collections_changed",\ndata: "revision":2}\n\n'),
          utf8.encode('data: {"kind":"revision","revision":2}'),
        ]),
        200,
      );
    });

    final events = await api.streamCollectionEvents().toList();
    expect(events.map((event) => event.kind), [
      AccountCollectionEventKind.ready,
      AccountCollectionEventKind.collectionsChanged,
      AccountCollectionEventKind.revision,
    ]);
    expect(events.map((event) => event.revision), [0, 2, 2]);
    expect(request!.url.path, '/api/account/collections/events');
    expect(request!.headers['Authorization'], 'Bearer session');
    expect(request!.headers['Accept'], 'text/event-stream');
  });

  test('cancelling account events releases an idle body immediately', () async {
    final listening = Completer<void>();
    var cancellations = 0;
    final body = StreamController<List<int>>(onListen: listening.complete, onCancel: () => cancellations++);
    addTearDown(body.close);
    final api = _api((_) async => http.StreamedResponse(body.stream, 200));
    final subscription = api.streamCollectionEvents().listen((_) {});
    await listening.future;

    await subscription.cancel().timeout(const Duration(seconds: 1));
    expect(cancellations, 1);
    expect(body.hasListener, isFalse);
  });

  test('unsupported event endpoint propagates HTTP status for capability fallback', () async {
    final api = _api((_) async => http.StreamedResponse(Stream.value(utf8.encode('not supported')), 404));

    await expectLater(
      api.streamCollectionEvents(),
      emitsError(isA<ApiException>().having((error) => error.statusCode, 'status', 404)),
    );
  });

  test('snapshots preserve unlike records and playlist versions', () {
    final snapshot = AccountCollectionSnapshot.fromJson({
      'user_id': 'listener',
      'revision': 9,
      'likes': [
        {'track_id': 'one', 'liked': true, 'updated_at': 2},
        {'track_id': 'two', 'liked': false, 'updated_at': 3},
      ],
      'playlists': [
        {
          'id': 'mix',
          'name': 'Mix',
          'revision': 4,
          'track_ids': ['two', 'three'],
        },
      ],
    });

    expect(snapshot.userId, 'listener');
    expect(snapshot.revision, 9);
    expect(snapshot.likedTrackIds, {'one'});
    expect(snapshot.playlistTrackIds, {'two', 'three'});
    expect(snapshot.likes.last.liked, isFalse);
    expect(() => snapshot.likes.clear(), throwsUnsupportedError);
    expect(() => snapshot.playlists.clear(), throwsUnsupportedError);
    expect(() => snapshot.playlists.first.trackIds.clear(), throwsUnsupportedError);
    expect(() => AccountCollectionSnapshot.fromJson({'revision': 0}), throwsFormatException);
  });

  test('collection capabilities default off for older servers', () {
    final oldServer = ServerCapabilities.fromJson({});
    final current = ServerCapabilities.fromJson({'account_collections_sync': '1', 'atomic_playlist_tracks': true});

    expect(oldServer.accountCollectionsSync, isFalse);
    expect(oldServer.atomicPlaylistTracks, isFalse);
    expect(current.accountCollectionsSync, isTrue);
    expect(current.atomicPlaylistTracks, isTrue);
  });
}

AccountEventsApi _api(Future<http.StreamedResponse> Function(http.BaseRequest) send) {
  final transport = ApiTransport(baseUrl: 'https://music.test/api', client: _StreamingClient(send));
  transport.setToken('session');

  return AccountEventsApi(transport);
}

class _StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;

  _StreamingClient(this._send);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}

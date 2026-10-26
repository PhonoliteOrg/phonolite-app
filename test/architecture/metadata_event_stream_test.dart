import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

void main() {
  test('cancelling an idle metadata stream releases its body immediately', () async {
    final listening = Completer<void>();
    var cancellations = 0;
    final body = StreamController<List<int>>(onListen: listening.complete, onCancel: () => cancellations++);
    addTearDown(body.close);
    final connection = _connection((_) async => http.StreamedResponse(body.stream, 200));
    final errors = <Object>[];
    final subscription = connection.streamMetadataEvents().listen((_) {}, onError: errors.add);
    await listening.future;

    await subscription.cancel().timeout(const Duration(seconds: 1));

    expect(cancellations, 1);
    expect(errors, isEmpty);
  });

  test('cancellation during a pending request cancels a late response body', () async {
    final sent = Completer<void>();
    final response = Completer<http.StreamedResponse>();
    final bodyCancelled = Completer<void>();
    final body = StreamController<List<int>>(onCancel: bodyCancelled.complete);
    addTearDown(body.close);
    final connection = _connection((_) {
      sent.complete();
      return response.future;
    });
    final errors = <Object>[];
    final subscription = connection.streamMetadataEvents().listen((_) {}, onError: errors.add);
    await sent.future;

    await subscription.cancel().timeout(const Duration(seconds: 1));
    response.complete(http.StreamedResponse(body.stream, 200));
    await bodyCancelled.future;

    expect(errors, isEmpty);
  });

  test('a request failure after cancellation is handled during shutdown', () async {
    final sent = Completer<void>();
    final response = Completer<http.StreamedResponse>();
    final connection = _connection((_) {
      sent.complete();
      return response.future;
    });
    final errors = <Object>[];
    final subscription = connection.streamMetadataEvents().listen((_) {}, onError: errors.add);
    await sent.future;

    await subscription.cancel().timeout(const Duration(seconds: 1));
    response.completeError(http.ClientException('Connection closed while receiving data'));
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
  });

  test('active metadata stream failures still reach the listener', () async {
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: listening.complete);
    addTearDown(body.close);
    final connection = _connection((_) async => http.StreamedResponse(body.stream, 200));
    final errors = <Object>[];
    final done = Completer<void>();
    connection.streamMetadataEvents().listen((_) {}, onError: errors.add, onDone: done.complete);
    await listening.future;
    final error = http.ClientException('Connection closed while receiving data');

    body.addError(error);
    await done.future;

    expect(errors, [same(error)]);
    expect(body.hasListener, isFalse);
  });

  test('metadata stream pauses and resumes its response body', () async {
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: listening.complete);
    addTearDown(body.close);
    final connection = _connection((_) async => http.StreamedResponse(body.stream, 200));
    final subscription = connection.streamMetadataEvents().listen((_) {});
    await listening.future;

    subscription.pause();
    expect(body.isPaused, isTrue);
    subscription.resume();
    expect(body.isPaused, isFalse);
    await subscription.cancel();
  });

  test('metadata frames survive chunk boundaries and a trailing frame', () async {
    http.BaseRequest? request;
    final body = Stream<List<int>>.fromIterable([
      utf8.encode(': keepalive\r\n\r\ndata: {"revision":1,"kind":"artist",'),
      utf8.encode('"id":"first"}\r'),
      utf8.encode('\n\r\ndata: not-json\n\ndata: {"revision":2,"kind":"album","id":"last"}'),
    ]);
    final connection = _connection((value) async {
      request = value;
      return http.StreamedResponse(body, 200);
    })..setToken('session-token');

    final events = await connection.streamMetadataEvents().toList();

    expect(events.map((event) => event.id), ['first', 'last']);
    expect(request!.url.path, '/api/library/metadata-events');
    expect(request!.headers['Authorization'], 'Bearer session-token');
  });

  test('metadata stream reports unsuccessful HTTP responses', () async {
    final connection = _connection(
      (_) async => http.StreamedResponse(Stream.value(utf8.encode('Session expired')), 401),
    );

    await expectLater(connection.streamMetadataEvents(), emitsError(isA<ApiException>()));
  });

  test('a paused stream cancels without delivering buffered metadata', () async {
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: listening.complete);
    addTearDown(body.close);
    final connection = _connection((_) async => http.StreamedResponse(body.stream, 200));
    final events = <MetadataUpdateEvent>[];
    final subscription = connection.streamMetadataEvents().listen(events.add);
    await listening.future;
    subscription.pause();
    body.add(utf8.encode('data: {"revision":1,"kind":"artist","id":"queued"}\n\n'));

    await subscription.cancel().timeout(const Duration(seconds: 1));

    expect(events, isEmpty);
    expect(body.hasListener, isFalse);
  });
}

ServerConnection _connection(Future<http.StreamedResponse> Function(http.BaseRequest) send) =>
    ServerConnection(baseUrl: 'https://example.test/api', client: _StreamingClient(send));

class _StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;

  _StreamingClient(this._send);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}

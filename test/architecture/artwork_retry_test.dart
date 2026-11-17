import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';
import 'package:phonolite_app/infrastructure/server/transport/streamed_response_body.dart';

void main() {
  group('bounded response body', () {
    Stream<List<int>> chunks(List<List<int>> parts) => Stream.fromIterable(parts);

    test('reads every chunk within the limit', () async {
      final bytes = await readBoundedBody(
        chunks([
          [1, 2],
          [3],
        ]),
        deadline: const Duration(seconds: 1),
        maximumBytes: 3,
        tooLarge: (_) => StateError('too large'),
      );

      expect(bytes, [1, 2, 3]);
    });

    test('an empty body returns empty bytes for the caller to judge', () async {
      final bytes = await readBoundedBody(
        chunks([]),
        deadline: const Duration(seconds: 1),
        maximumBytes: 3,
        tooLarge: (_) => StateError('too large'),
      );

      expect(bytes, isEmpty);
    });

    test('passing the limit reports the length the body would have reached', () async {
      int? reported;

      await expectLater(
        readBoundedBody(
          chunks([
            [1, 2],
            [3, 4, 5],
          ]),
          deadline: const Duration(seconds: 1),
          maximumBytes: 4,
          tooLarge: (length) {
            reported = length;

            return StateError('too large');
          },
        ),
        throwsStateError,
      );
      expect(reported, 5);
    });

    test('one deadline covers the whole body', () async {
      final slow = StreamController<List<int>>();

      slow.add([1]);

      await expectLater(
        readBoundedBody(
          slow.stream,
          deadline: const Duration(milliseconds: 20),
          maximumBytes: 10,
          tooLarge: (_) => StateError('too large'),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await slow.close();
    });
  });

  group('bounded Retry-After', () {
    http.Response withRetryAfter(String? value) =>
        http.Response('', 503, headers: {if (value != null) HttpHeaders.retryAfterHeader: value});

    test('keeps a cooldown between one second and one minute', () {
      expect(boundedRetryAfter(withRetryAfter('7')), const Duration(seconds: 7));
      expect(boundedRetryAfter(withRetryAfter('0')), const Duration(seconds: 1));
      expect(boundedRetryAfter(withRetryAfter('600')), const Duration(minutes: 1));
    });

    test('accepts an HTTP date and ignores a missing or malformed value', () {
      final later = HttpDate.format(DateTime.now().add(const Duration(minutes: 10)));

      expect(boundedRetryAfter(withRetryAfter(later)), const Duration(minutes: 1));
      expect(boundedRetryAfter(withRetryAfter(null)), isNull);
      expect(boundedRetryAfter(withRetryAfter('soon')), isNull);
    });
  });

  group('streamed request retries', () {
    test('a retried streamed response releases its body before the next attempt', () async {
      final released = <bool>[];
      var attempts = 0;
      final transport = ApiTransport(
        baseUrl: 'https://server.test/api',
        client: MockClient((_) async => http.Response('', 200)),
      );

      final response = await transport.executeRequest(() async {
        attempts++;

        if (attempts == 1) {
          final body = StreamController<List<int>>(onCancel: () => released.add(true));
          addTearDown(body.close);

          return http.StreamedResponse(body.stream, 503, headers: {HttpHeaders.retryAfterHeader: '0'});
        }

        return http.StreamedResponse(Stream.value([1]), 200);
      }, retryable: true);

      expect(attempts, 2);
      expect(released, [true]);
      expect(response.statusCode, 200);
    });

    test('beforeRetry can stop a request from being retried', () async {
      var attempts = 0;
      final transport = ApiTransport(
        baseUrl: 'https://server.test/api',
        client: MockClient((_) async => http.Response('', 200)),
      );

      await expectLater(
        transport.executeRequest(
          () async {
            attempts++;

            return http.StreamedResponse(Stream.value([1]), 503, headers: {HttpHeaders.retryAfterHeader: '0'});
          },
          retryable: true,
          beforeRetry: () => throw StateError('session changed'),
        ),
        throwsStateError,
      );
      expect(attempts, 1);
    });
  });

  group('artwork downloads', () {
    ServerConnection connectionReplying(Future<http.Response> Function(int attempt) reply) {
      var attempts = 0;
      final connection = ServerConnection(
        baseUrl: 'https://server.test/api',
        client: MockClient((_) => reply(++attempts)),
      );

      connection.setToken('token');

      return connection;
    }

    test('a busy server is retried through the shared transport policy', () async {
      final seen = <int>[];
      final connection = connectionReplying((attempt) async {
        seen.add(attempt);

        return attempt < 3
            ? http.Response('busy', 503, headers: {HttpHeaders.retryAfterHeader: '0'})
            : http.Response.bytes([1, 2, 3], 200, headers: {HttpHeaders.contentTypeHeader: 'image/png'});
      });

      final artwork = await connection.fetchAlbumCoverBytes('album');

      expect(seen, [1, 2, 3]);
      expect(artwork?.bytes, [1, 2, 3]);
      expect(artwork?.contentType, 'image/png');
    });

    test('a dropped connection is retried', () async {
      final connection = connectionReplying((attempt) async {
        if (attempt == 1) {
          throw http.ClientException('connection reset');
        }

        return http.Response.bytes([4], 200);
      });

      expect((await connection.fetchAlbumCoverBytes('album'))?.bytes, [4]);
    });

    test('a long cooldown returns to the caller with the requested delay', () async {
      final seen = <int>[];
      final connection = connectionReplying((attempt) async {
        seen.add(attempt);

        return http.Response('busy', 429, headers: {HttpHeaders.retryAfterHeader: '120'});
      });

      await expectLater(
        connection.fetchAlbumCoverBytes('album'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'status', 429)
              .having((error) => error.retryAfter, 'retryAfter', const Duration(seconds: 120)),
        ),
      );
      expect(seen, [1]);
    });

    test('missing artwork is null without a retry', () async {
      final seen = <int>[];
      final connection = connectionReplying((attempt) async {
        seen.add(attempt);

        return http.Response('', 404);
      });

      expect(await connection.fetchAlbumCoverBytes('album'), isNull);
      expect(seen, [1]);
    });
  });
}

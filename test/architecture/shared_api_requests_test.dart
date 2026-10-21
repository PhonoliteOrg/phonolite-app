import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

void main() {
  test('GET and POST lists share flat and items-envelope decoding', () async {
    for (final body in [
      jsonEncode([
        {'id': 'track'},
      ]),
      jsonEncode({
        'items': [
          {'id': 'track'},
        ],
      }),
    ]) {
      final client = MockClient((_) async => http.Response(body, 200));
      addTearDown(client.close);
      final transport = ApiTransport(
        baseUrl: 'http://example.test/api/v1',
        client: client,
      );
      expect(await transport.getList('/items'), [
        {'id': 'track'},
      ]);
      expect(await transport.postList('/items', {}), [
        {'id': 'track'},
      ]);
    }
  });

  test(
    'response status is checked before either JSON shape is decoded',
    () async {
      const decoder = ApiResponseDecoder();
      final response = http.Response('not JSON', 403);
      final failure = isA<ApiException>().having(
        (error) => error.statusCode,
        'statusCode',
        403,
      );
      await expectLater(decoder.object(response), throwsA(failure));
      await expectLater(
        decoder.list(response, path: '/items'),
        throwsA(failure),
      );
      expect(() => decoder.requireSuccess(response), throwsA(failure));
    },
  );

  test(
    'large object and list payloads retain the same decoded values',
    () async {
      const decoder = ApiResponseDecoder();
      final value = {'text': List.filled(70 * 1024, 'x').join()};
      expect(
        await decoder.object(http.Response(jsonEncode(value), 200)),
        value,
      );
      expect(
        await decoder.list(
          http.Response(jsonEncode([value]), 200),
          path: '/items',
        ),
        [value],
      );
    },
  );

  test(
    'a retried list read keeps its originating server and credentials',
    () async {
      final requests = <http.Request>[];
      late final ApiTransport transport;
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          transport.setBaseUrl('http://second.test/api/v1');
          transport.setToken('second-token');
          return http.Response('retry', 503);
        }
        return http.Response('[]', 200);
      });
      addTearDown(client.close);
      transport = _ImmediateRetryTransport(client)..setToken('first-token');

      await transport.getList('/items');
      await transport.getList('/items');

      expect(requests.map((request) => request.url.host), [
        'first.test',
        'first.test',
        'second.test',
      ]);
      expect(requests.map((request) => request.headers['Authorization']), [
        'Bearer first-token',
        'Bearer first-token',
        'Bearer second-token',
      ]);
    },
  );
}

class _ImmediateRetryTransport extends ApiTransport {
  _ImmediateRetryTransport(http.Client client)
    : super(baseUrl: 'http://first.test/api/v1', client: client);

  @override
  Duration retryDelay(int attempt) => Duration.zero;
}

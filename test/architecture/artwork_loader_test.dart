import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonolite_app/platform/now_playing_artwork_loader.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/entities/server_trust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'remote artwork forwards credentials and decodes only successful responses',
    () async {
      final requests = <http.Request>[];
      var decodeCount = 0;
      final loader = NowPlayingArtworkLoader(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes([
            1,
            2,
          ], request.url.path == '/missing' ? 404 : 200);
        }),
        decode: (bytes) async {
          decodeCount++;
          return Uint8List.fromList([...bytes, 3]);
        },
      );
      expect(
        await loader.loadRemote('https://server.test/art', token: 'token'),
        [1, 2, 3],
      );
      expect(requests.first.headers['Authorization'], 'Bearer token');
      expect(
        await loader.loadRemote('https://server.test/missing', token: ''),
        isNull,
      );
      expect(requests.last.headers.containsKey('Authorization'), isFalse);
      expect(decodeCount, 1);
    },
  );

  test('network and decoding failures are optional artwork misses', () async {
    final unavailable = NowPlayingArtworkLoader(
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    expect(
      await unavailable.loadRemote('https://server.test/art', token: ''),
      isNull,
    );
    final corrupt = NowPlayingArtworkLoader(
      client: MockClient((_) async => http.Response.bytes([1], 200)),
      decode: (_) async => throw const FormatException('invalid image'),
    );
    expect(
      await corrupt.loadRemote('https://server.test/art', token: ''),
      isNull,
    );
  });

  test(
    'file loading shares decoding behavior and tolerates missing files',
    () async {
      final temp = await Directory.systemTemp.createTemp('phonolite_art_test_');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/art');
      await file.writeAsBytes([4, 5]);
      final loader = NowPlayingArtworkLoader(decode: (bytes) async => bytes);
      expect(await loader.loadFile(file.path), [4, 5]);
      expect(await loader.loadFile('${temp.path}/missing'), isNull);
    },
  );

  test('native decoder returns PNG bytes and handles corrupt images', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
    );
    final loader = NowPlayingArtworkLoader(
      client: MockClient(
        (request) async => http.Response.bytes(
          request.url.path == '/valid' ? png : [1, 2],
          200,
        ),
      ),
    );
    final decoded = await loader.loadRemote(
      'https://server.test/valid',
      token: '',
    );
    expect(decoded, isNotNull);
    expect(decoded!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(
      await loader.loadRemote('https://server.test/corrupt', token: ''),
      isNull,
    );
  });

  test(
    'authenticated resource headers track sessions without exposing mutable state',
    () {
      final connection = ServerConnection(baseUrl: 'https://server.test');
      connection.setTrust(ServerTrust(spki: 'ab' * 32, opaqueKey: 'test-key'));
      expect(connection.authorizationHeaders, isEmpty);
      connection.setToken('first');
      final headers = connection.authorizationHeaders;
      expect(headers, {'Authorization': 'Bearer first'});
      headers.clear();
      expect(connection.authorizationHeaders, {
        'Authorization': 'Bearer first',
      });
      connection.setToken('next');
      expect(connection.authorizationHeaders, {'Authorization': 'Bearer next'});
      connection.setToken(null);
      expect(connection.authorizationHeaders, isEmpty);
    },
  );
}

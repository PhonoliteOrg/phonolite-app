import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/data/storage/artwork/artwork_disk_cache.dart';
import 'package:phonolite_app/infrastructure/artwork/managed_artwork_loader.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

// A structurally complete JPEG stream. Frame decoding is tested separately by
// the image-provider tests; this fixture exercises marker completeness only.
final _jpeg = Uint8List.fromList([
  0xff,
  0xd8,
  0xff,
  0xc0,
  0,
  11,
  8,
  0,
  1,
  0,
  1,
  1,
  1,
  0x11,
  0,
  0xff,
  0xda,
  0,
  8,
  1,
  1,
  0,
  0,
  63,
  0,
  1,
  2,
  3,
  0xff,
  0xd9,
]);

void main() {
  test('unknown-length JPEG responses still require a complete codestream', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-chunked-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient.streaming((_, _) async {
        requests++;
        final bytes = requests == 1 ? Uint8List.sublistView(_jpeg, 0, _jpeg.length - 2) : _jpeg;
        return http.StreamedResponse(Stream.value(bytes), 200, headers: {'cache-control': 'max-age=3600'});
      }),
    );
    final loader = ManagedArtworkLoader(
      connection: connection,
      disk: ArtworkDiskCache(directory: () async => directory),
    );
    addTearDown(loader.close);
    final request = ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover');
    await expectLater(loader.load(request), throwsA(isA<ArtworkLoadException>()));
    expect(await directory.list().length, 0);
    expect(await loader.load(request), _jpeg);
    expect(requests, 2);
  });

  test('valid stored artwork keeps conditional 304 reuse working', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-valid-revalidation-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          expect(request.headers['if-none-match'], isNull);
          return http.Response.bytes(_jpeg, 200, headers: {'cache-control': 'no-cache', 'etag': '"complete"'});
        }
        expect(request.headers['if-none-match'], '"complete"');
        return http.Response('', 304);
      }),
    );
    final loader = ManagedArtworkLoader(
      connection: connection,
      disk: ArtworkDiskCache(directory: () async => directory),
    );
    addTearDown(loader.close);
    ArtworkRequest request() => ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover');
    expect(await loader.load(request()), _jpeg);
    expect(await loader.load(request()), _jpeg);
    expect(requests, 2);
  });

  for (final failure in ['short', 'long', 'jpeg']) {
    test('a $failure artwork response is rejected without poisoning the disk cache', () async {
      final directory = await Directory.systemTemp.createTemp('phonolite-artwork-incomplete-');
      addTearDown(() => directory.delete(recursive: true));
      var requests = 0;
      final connection = ServerConnection(
        baseUrl: 'https://music.test/api',
        client: MockClient.streaming((_, _) async {
          requests++;
          final bytes = requests == 1 && failure == 'jpeg' ? Uint8List.sublistView(_jpeg, 0, _jpeg.length - 2) : _png;
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: requests == 1 && failure != 'jpeg'
                ? bytes.length + (failure == 'short' ? 5 : -5)
                : bytes.length,
            headers: {'cache-control': 'private, max-age=3600', 'etag': '"unchanged-source"'},
          );
        }),
      );
      final loader = ManagedArtworkLoader(
        connection: connection,
        disk: ArtworkDiskCache(directory: () async => directory),
      );
      addTearDown(loader.close);
      final request = ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover');
      await expectLater(loader.load(request), throwsA(isA<ArtworkLoadException>()));
      expect(await directory.list().length, 0);
      expect(await loader.load(request), _png);
      expect(requests, 2);
      expect(await loader.load(request), _png);
      expect(requests, 2);
    });
  }

  test('decompressed artwork is not compared to the compressed Content-Length', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-compressed-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(_png),
          200,
          contentLength: 10,
          headers: {'content-encoding': 'gzip', 'cache-control': 'no-store'},
        ),
      ),
    );
    final loader = ManagedArtworkLoader(
      connection: connection,
      disk: ArtworkDiskCache(directory: () async => directory),
    );
    addTearDown(loader.close);
    expect(await loader.load(ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover')), _png);
  });

  for (final fresh in [false, true]) {
    test('legacy truncated JPEG is removed before ${fresh ? 'fresh-cache reuse' : 'ETag revalidation'}', () async {
      final directory = await Directory.systemTemp.createTemp('phonolite-artwork-legacy-');
      addTearDown(() => directory.delete(recursive: true));
      var requests = 0;
      final connection = ServerConnection(
        baseUrl: 'https://music.test/api',
        client: MockClient((request) async {
          requests++;
          expect(request.headers['if-none-match'], isNull, reason: 'Corrupt bytes must never be reused via a 304.');
          return http.Response.bytes(_png, 200, headers: {'cache-control': 'max-age=3600'});
        }),
      );
      final loader = ManagedArtworkLoader(
        connection: connection,
        disk: ArtworkDiskCache(directory: () async => directory),
      );
      addTearDown(loader.close);
      final request = ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover');
      final key = sha256.convert(utf8.encode(jsonEncode([loader.cacheScope, request.source]))).toString();
      await _writeLegacyCache(
        directory,
        key,
        Uint8List.sublistView(_jpeg, 0, _jpeg.length - 2),
        expires: DateTime.now().add(fresh ? const Duration(hours: 1) : const Duration(hours: -1)),
      );
      expect(await loader.load(request), _png);
      expect(requests, 1);
      expect(await loader.load(request), _png);
      expect(requests, 1);
    });
  }

  test('complete legacy JPEGs retain their cache freshness and validators', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-valid-legacy-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ArtworkDiskCache(directory: () async => directory);
    addTearDown(cache.close);
    final key = 'c' * 64;
    final expires = DateTime.now().add(const Duration(hours: 1));
    await _writeLegacyCache(directory, key, _jpeg, expires: expires);
    final read = await cache.read(key);
    expect(read?.bytes, _jpeg);
    expect(read?.etag, '"unchanged-source"');
    expect(read?.expiresAt.millisecondsSinceEpoch, expires.millisecondsSinceEpoch);
  });

  test('cache integrity checks detect partial writes and altered bytes', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-integrity-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ArtworkDiskCache(directory: () async => directory);
    addTearDown(cache.close);
    for (final truncate in [false, true]) {
      final key = (truncate ? 'a' : 'b') * 64;
      await cache.write(key, StoredArtwork(bytes: _png, expiresAt: DateTime.utc(2030)));
      final file = File('${directory.path}${Platform.pathSeparator}$key.art');
      var bytes = await file.readAsBytes();
      if (truncate) {
        bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      } else {
        bytes[bytes.length - 1] ^= 1;
      }
      await file.writeAsBytes(bytes, flush: true);
      expect(await cache.read(key), isNull);
      expect(await file.exists(), isFalse);
    }
  });

  test('an old frame failure cannot remove newer bytes for the same artwork key', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-new-generation-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(requests == 1 ? _jpeg : _png, 200, headers: {'cache-control': 'no-cache'});
      }),
    );
    final disk = ArtworkDiskCache(directory: () async => directory);
    final loader = ManagedArtworkLoader(connection: connection, disk: disk);
    addTearDown(loader.close);
    ArtworkRequest request() => ArtworkRequest(source: 'https://music.test/api/library/albums/album/cover');
    final old = request();
    expect(await loader.load(old), _jpeg);
    final current = request();
    expect(await loader.load(current), _png);
    await loader.invalidate(old);
    expect(await directory.list().length, 1);
    await loader.invalidate(current);
    expect(await directory.list().length, 0);
  });

  test('codec admission bounds the complete load callback before bytes allocate', () async {
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((_) async => http.Response('', 404)),
    );
    final loader = ManagedArtworkLoader(connection: connection);
    addTearDown(loader.close);
    final release = Completer<void>();
    var active = 0;
    var peak = 0;
    final loads = [
      for (var index = 0; index < 40; index++)
        loader
            .decode(loader.cacheScope, () async {
              active++;
              if (active > peak) peak = active;
              await release.future;
              active--;

              return true;
            })
            .then<Object>((value) => value, onError: (Object error) => error),
    ];
    expect(active, 2);
    release.complete();
    final results = await Future.wait(loads);
    expect(peak, 2);
    expect(results.whereType<bool>(), hasLength(34));
    expect(results.whereType<ArtworkLoadException>(), hasLength(6));
  });

  test('warm images survive a loader restart and scopes isolate account bytes', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-cache-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((request) async {
        requests++;
        expect(request.url.queryParameters['size'], '128');
        expect(request.headers['Authorization'], 'Bearer secret-session');

        return http.Response.bytes(_png, 200, headers: {'cache-control': 'private, max-age=31536000, immutable'});
      }),
    )..setToken('secret-session');
    var account = 'first-account';
    ArtworkDiskCache storage() => ArtworkDiskCache(directory: () async => directory);
    final first = ManagedArtworkLoader(connection: connection, accountScope: () => account, disk: storage());
    final request = ArtworkRequest(
      source: 'https://music.test/api/library/artists/a/cover?kind=logo&v=logo',
      decodeSize: 64,
    );
    expect(await first.load(request), _png);
    await first.close();

    final second = ManagedArtworkLoader(connection: connection, accountScope: () => account, disk: storage());
    addTearDown(second.close);
    expect(await second.load(request), _png);
    expect(requests, 1);
    account = 'second-account';
    expect(await second.load(request), _png);
    expect(requests, 2);

    for (final file in directory.listSync()) {
      expect(file.path, isNot(contains('secret-session')));
      expect(file.path, isNot(contains('first-account')));
    }
  });

  test('same-key floods share one load and overflow is retryable', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-coalescing-');
    addTearDown(() => directory.delete(recursive: true));
    final release = Completer<void>();
    var requests = 0;
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((_) async {
        requests++;
        await release.future;

        return http.Response.bytes(_png, 200, headers: {'cache-control': 'no-store'});
      }),
    )..setToken('session');
    final loader = ManagedArtworkLoader(
      connection: connection,
      disk: ArtworkDiskCache(directory: () async => directory),
    );
    addTearDown(loader.close);
    final results = [
      for (var index = 0; index < 100; index++)
        loader
            .load(ArtworkRequest(source: 'https://music.test/api/library/artists/a/cover'))
            .then<Object>((bytes) => bytes, onError: (Object error) => error),
    ];
    release.complete();
    final completed = await Future.wait(results);
    expect(requests, 1);
    expect(completed.whereType<Uint8List>(), hasLength(32));
    expect(completed.whereType<ArtworkLoadException>(), hasLength(68));
    expect(completed.whereType<ArtworkLoadException>().every((error) => error.statusCode == 503), isTrue);
  });

  test('a changed session cannot publish pending artwork', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-session-');
    addTearDown(() => directory.delete(recursive: true));
    final started = Completer<void>();
    final release = Completer<void>();
    final connection = ServerConnection(
      baseUrl: 'https://music.test/api',
      client: MockClient((_) async {
        started.complete();
        await release.future;

        return http.Response.bytes(_png, 200, headers: {'cache-control': 'private, max-age=31536000, immutable'});
      }),
    )..setToken('first');
    final loader = ManagedArtworkLoader(
      connection: connection,
      disk: ArtworkDiskCache(directory: () async => directory),
    );
    addTearDown(loader.close);
    final load = loader.load(ArtworkRequest(source: 'https://music.test/api/library/artists/a/cover'));
    final expected = expectLater(load, throwsA(isA<ArtworkLoadException>()));
    await started.future;
    connection.setToken('second');
    release.complete();
    await expected;
    expect(await directory.list().length, 0);
  });

  test('disposable storage removes corrupt files and enforces its file quota', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-artwork-prune-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ArtworkDiskCache(directory: () async => directory, maximumFiles: 1);
    addTearDown(cache.close);
    final firstKey = 'a' * 64;
    final secondKey = 'b' * 64;
    await cache.write(firstKey, StoredArtwork(bytes: _png, expiresAt: DateTime.utc(2030)));
    await cache.write(secondKey, StoredArtwork(bytes: _png, expiresAt: DateTime.utc(2030)));
    expect(await directory.list().length, 1);
    expect(await cache.read(firstKey), isNull);
    final file = File('${directory.path}${Platform.pathSeparator}$secondKey.art');
    await file.writeAsBytes([1, 2, 3]);
    expect(await cache.read(secondKey), isNull);
    expect(await file.exists(), isFalse);
  });
}

Future<void> _writeLegacyCache(Directory directory, String key, Uint8List bytes, {required DateTime expires}) async {
  final header = utf8.encode(jsonEncode({'expires': expires.millisecondsSinceEpoch, 'etag': '"unchanged-source"'}));
  final headerLength = ByteData(4)..setUint32(0, header.length);
  await File(
    '${directory.path}${Platform.pathSeparator}$key.art',
  ).writeAsBytes([...headerLength.buffer.asUint8List(), ...header, ...bytes], flush: true);
}

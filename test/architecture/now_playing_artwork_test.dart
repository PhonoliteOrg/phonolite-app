import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/playback/now_playing_artwork.dart';
import 'package:phonolite_app/infrastructure/artwork/now_playing_artwork_loader.dart';

void main() {
  test('late results cannot replace newer artwork or release its request', () async {
    final loader = _Loader();
    final artwork = NowPlayingArtwork(loader: loader);
    final first = artwork.load(url: 'first', sessionRevision: 1);
    final second = artwork.load(url: 'second', sessionRevision: 1);
    loader.requests[0].complete(Uint8List.fromList([1]));
    expect(await first, isFalse);
    expect(await artwork.load(url: 'second', sessionRevision: 1), isFalse);
    expect(loader.requests, hasLength(2));
    loader.requests[1].complete(Uint8List.fromList([2]));
    expect(await second, isTrue);
    expect(artwork.key, 'url:second');
    expect(artwork.bytes, [2]);
    expect(() => artwork.bytes![0] = 3, throwsUnsupportedError);
  });

  test('clear invalidates pending work and permits reloading the same source', () async {
    final loader = _Loader();
    final artwork = NowPlayingArtwork(loader: loader);
    final first = artwork.load(url: 'cover', sessionRevision: 1);
    artwork.clear();
    loader.requests.single.complete(Uint8List.fromList([1]));
    expect(await first, isFalse);
    expect(artwork.bytes, isNull);
    expect(artwork.key, isNull);
    final next = artwork.load(url: 'cover', sessionRevision: 1);
    loader.requests.last.complete(Uint8List.fromList([2]));
    expect(await next, isTrue);
  });

  test('local paths take priority; session changes invalidate the cached source', () async {
    final loader = _Loader();
    final artwork = NowPlayingArtwork(loader: loader);
    final first = artwork.load(url: 'remote', localPath: ' local ', sessionRevision: 1);
    expect(loader.sources, ['file:local']);
    loader.requests.last.complete(Uint8List.fromList([1]));
    expect(await first, isTrue);
    expect(await artwork.load(localPath: 'local', sessionRevision: 1), isFalse);
    final changed = artwork.load(localPath: 'local', sessionRevision: 2);
    expect(artwork.bytes, isNull);
    loader.requests.last.complete(Uint8List.fromList([2]));
    expect(await changed, isTrue);
    await artwork.load(sessionRevision: 0);
    expect(artwork.key, isNull);
    expect(artwork.bytes, isNull);
  });

  test('failed requests can be retried', () async {
    final loader = _Loader();
    final artwork = NowPlayingArtwork(loader: loader);
    final first = artwork.load(url: 'cover', sessionRevision: 0);
    loader.requests.last.complete(null);
    expect(await first, isFalse);
    final retry = artwork.load(url: 'cover', sessionRevision: 0);
    loader.requests.last.complete(Uint8List.fromList([1]));
    expect(await retry, isTrue);
  });
}

class _Loader extends NowPlayingArtworkLoader {
  final requests = <Completer<Uint8List?>>[];
  final sources = <String>[];
  Future<Uint8List?> _request(String source) {
    sources.add(source);
    final request = Completer<Uint8List?>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<Uint8List?> loadFile(String path) => _request('file:$path');
  @override
  Future<Uint8List?> loadRemote(String url, {required int sessionRevision}) => _request('url:$url:$sessionRevision');
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/decoded_artwork_preloader.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class _Loader implements ArtworkLoader {
  @override
  String cacheScope = 'account-a';
  final List<String> calls = [];
  final Map<String, Completer<Uint8List>> pending = {};
  final Map<String, Completer<void>> _requested = {};

  Future<void> whenRequested(String source) => _requested.putIfAbsent(source, Completer<void>.new).future;

  @override
  Future<Uint8List> load(ArtworkRequest request) {
    calls.add('$cacheScope:${request.source}');
    final requested = _requested.putIfAbsent(request.source, Completer<void>.new);
    if (!requested.isCompleted) requested.complete();
    return pending[request.source]?.future ?? Future.value(_png);
  }

  @override
  Future<T> decode<T>(String scope, Future<T> Function() operation) => operation();

  @override
  Future<void> invalidate(ArtworkRequest request) async {}

  @override
  Future<void> close() async {}
}

AuthenticatedNetworkImage _provider(_Loader loader, ArtworkRequest request) =>
    AuthenticatedNetworkImage(request.source, loader: loader, headers: request.headers, decodeSize: request.decodeSize);

Future<void> _firstFrame(ImageProvider provider) async {
  final result = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) {
      info.dispose();
      if (!result.isCompleted) result.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await result.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  late int previousCacheLimit;

  setUp(() {
    final cache = PaintingBinding.instance.imageCache;
    previousCacheLimit = cache.maximumSizeBytes;
    cache.clear();
    cache.clearLiveImages();
    cache.maximumSizeBytes = 0;
  });

  tearDown(() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    cache.maximumSizeBytes = previousCacheLimit;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows artwork renders its first frame synchronously from the warmed key', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final loader = _Loader();
      final preloader = DecodedArtworkPreloader(loader: loader);
      addTearDown(preloader.dispose);
      final request = ArtworkRequest(
        source: 'https://music.test/cover',
        headers: const {'Authorization': 'Bearer token'},
      );
      await tester.runAsync(() async {
        preloader.update([request]);
        await _firstFrame(_provider(loader, request));
      });

      bool? synchronousFrame;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Image(
            image: _provider(loader, request),
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null) synchronousFrame = synchronous;
              return child;
            },
          ),
        ),
      );
      expect(synchronousFrame, isTrue);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(loader.calls, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('live pins survive a zero-byte cache and clear releases their lookup keys', (tester) async {
    final loader = _Loader();
    final preloader = DecodedArtworkPreloader(loader: loader);
    addTearDown(preloader.dispose);
    final request = ArtworkRequest(source: 'live-cover');
    final provider = _provider(loader, request);
    await tester.runAsync(() async {
      preloader.update([request, request]);
      await _firstFrame(provider);
    });

    final cache = PaintingBinding.instance.imageCache;
    expect(cache.statusForKey(provider).live, isTrue);
    expect(cache.statusForKey(provider).keepAlive, isFalse);
    await tester.runAsync(() => _firstFrame(_provider(loader, request)));
    expect(loader.calls, hasLength(1));
    preloader.clear();
    expect(cache.statusForKey(provider).live, isFalse);
  });

  testWidgets('scope replacement discards a pending old account without reviving its pin', (tester) async {
    final loader = _Loader();
    final preloader = DecodedArtworkPreloader(loader: loader);
    addTearDown(preloader.dispose);
    final oldRequest = ArtworkRequest(source: 'old-cover');
    final oldProvider = _provider(loader, oldRequest);
    final request = ArtworkRequest(source: 'new-cover');
    await tester.runAsync(() async {
      final oldBytes = Completer<Uint8List>();
      loader.pending['old-cover'] = oldBytes;
      preloader.update([oldRequest]);
      final oldResult = expectLater(_firstFrame(oldProvider), throwsA(isA<ArtworkLoadException>()));
      await loader.whenRequested(oldRequest.source);
      loader.cacheScope = 'account-b';
      preloader.update([request]);
      await _firstFrame(_provider(loader, request));
      oldBytes.complete(_png);
      await oldResult;
    });
    await tester.pump();
    expect(PaintingBinding.instance.imageCache.statusForKey(oldProvider).live, isFalse);
    expect(PaintingBinding.instance.imageCache.statusForKey(_provider(loader, request)).live, isTrue);
    preloader.dispose();
    expect(PaintingBinding.instance.imageCache.statusForKey(_provider(loader, request)).live, isFalse);
  });

  testWidgets('failed covers release listeners and do not retry on unchanged updates', (tester) async {
    final loader = _Loader();
    final preloader = DecodedArtworkPreloader(loader: loader);
    addTearDown(preloader.dispose);
    final request = ArtworkRequest(source: 'missing-cover');
    await tester.runAsync(() async {
      final failure = Completer<Uint8List>();
      loader.pending['missing-cover'] = failure;
      preloader.update([request]);
      final observed = _firstFrame(_provider(loader, request));
      await loader.whenRequested(request.source);
      failure.completeError(const ArtworkLoadException(statusCode: 404));
      await expectLater(observed, throwsA(isA<ArtworkLoadException>()));
      await Future<void>.delayed(Duration.zero);
    });
    preloader.update([request]);
    expect(loader.calls, hasLength(1));
    expect(PaintingBinding.instance.imageCache.statusForKey(_provider(loader, request)).live, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing an in-flight window handles its later optional failure', (tester) async {
    final loader = _Loader();
    final preloader = DecodedArtworkPreloader(loader: loader);
    addTearDown(preloader.dispose);
    final request = ArtworkRequest(source: 'abandoned-cover');
    await tester.runAsync(() async {
      final failure = Completer<Uint8List>();
      loader.pending['abandoned-cover'] = failure;
      preloader.update([request]);
      await loader.whenRequested(request.source);
      preloader.clear();
      failure.completeError(const ArtworkLoadException(statusCode: 404));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(PaintingBinding.instance.imageCache.statusForKey(_provider(loader, request)).live, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained entry count and decoded byte budget are bounded', (tester) async {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024;
    final loader = _Loader();
    final preloader = DecodedArtworkPreloader(loader: loader, maximumBytes: 8);
    addTearDown(preloader.dispose);
    final requests = [for (var i = 0; i < 4; i++) ArtworkRequest(source: 'cover-$i')];
    await tester.runAsync(() async {
      preloader.update(requests);
      for (final request in requests.take(3)) {
        await _firstFrame(_provider(loader, request));
      }
    });
    final cache = PaintingBinding.instance.imageCache;
    expect(loader.calls, hasLength(3));
    expect(cache.statusForKey(_provider(loader, requests[0])).live, isTrue);
    expect(cache.statusForKey(_provider(loader, requests[1])).live, isTrue);
    expect(cache.statusForKey(_provider(loader, requests[2])).live, isFalse);
    expect(cache.statusForKey(_provider(loader, requests[3])).live, isFalse);

    await tester.runAsync(() async {
      preloader.update(requests.skip(1));
      await _firstFrame(_provider(loader, requests[2]));
      await _firstFrame(_provider(loader, requests[3]));
    });
    expect(cache.statusForKey(_provider(loader, requests[0])).live, isFalse);
    expect(cache.statusForKey(_provider(loader, requests[1])).live, isTrue);
    expect(cache.statusForKey(_provider(loader, requests[2])).live, isTrue);
    expect(cache.statusForKey(_provider(loader, requests[3])).live, isFalse);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';
import '../support/artwork_test_loader.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

Future<Object?> _load(ImageProvider provider) async {
  final result = Completer<Object?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((image, _) {
    image.dispose();
    result.complete(null);
  }, onError: (error, _) => result.complete(error));
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final failure in ['http', 'decode']) {
    test('a $failure failure does not poison later artwork loads for the same account', () async {
      final client = _Client(failure);
      final original = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => client;
      addTearDown(() => debugNetworkImageHttpClientProvider = original);
      const url = 'https://music.test/api/library/artists/artist/cover?kind=logo';
      AuthenticatedNetworkImage provider() => AuthenticatedNetworkImage(
        url,
        loader: ArtworkTestLoader(client: client),
        headers: {'Authorization': 'Bearer first'},
      );

      expect(await _load(provider()), isNotNull);
      await Future<void>.delayed(Duration.zero);
      final retried = await _load(provider());
      expect(client.requests, 2, reason: 'A failed cache entry must allow a new HTTP request.');
      expect(retried, isNull);
      expect(await _load(provider()), isNull);
      expect(client.requests, 2, reason: 'Successful images should still be cached.');
    });
  }

  test('a failed first frame invalidates its bytes and permits the same image to load again', () async {
    final loader = _LifecycleLoader(failFirstFrame: true);
    AuthenticatedNetworkImage provider() =>
        AuthenticatedNetworkImage('https://music.test/api/library/albums/frame-failure/cover', loader: loader);

    expect(await _load(provider()), isA<StateError>());
    await Future<void>.delayed(Duration.zero);
    expect(loader.invalidated, [same(loader.loaded.single)]);
    expect(PaintingBinding.instance.imageCache.containsKey(provider()), isFalse);

    expect(await _load(provider()), isNull);
    expect(loader.loaded, hasLength(2));
    expect(await _load(provider()), isNull);
    expect(loader.loaded, hasLength(2), reason: 'The successful replacement should remain cached.');
  });

  test('decode admission failure does not poison the image key or invalidate valid disk bytes', () async {
    final loader = _LifecycleLoader(rejectFirstAdmission: true);
    AuthenticatedNetworkImage provider() =>
        AuthenticatedNetworkImage('https://music.test/api/library/albums/admission-failure/cover', loader: loader);

    expect(await _load(provider()), isA<ArtworkLoadException>());
    await Future<void>.delayed(Duration.zero);
    expect(loader.loaded, isEmpty);
    expect(loader.invalidated, isEmpty);
    expect(PaintingBinding.instance.imageCache.containsKey(provider()), isFalse);

    expect(await _load(provider()), isNull);
    expect(loader.loaded, hasLength(1));
  });

  test('a retry waits for failed frame bytes to be removed before loading', () async {
    final invalidation = Completer<void>();
    final loader = _LifecycleLoader(failFirstFrame: true, invalidationGate: invalidation);
    AuthenticatedNetworkImage provider() =>
        AuthenticatedNetworkImage('https://music.test/api/library/albums/delayed-invalidation/cover', loader: loader);

    expect(await _load(provider()), isA<StateError>());
    await Future<void>.delayed(Duration.zero);
    final retry = _load(provider());
    await Future<void>.delayed(Duration.zero);
    expect(loader.loaded, hasLength(1));
    expect(loader.invalidated, hasLength(1));

    invalidation.complete();
    expect(await retry, isNull);
    expect(loader.loaded, hasLength(2));
  });

  test('a late failed frame cannot evict a newer successful load for the same key', () async {
    final frameFailure = Completer<void>();
    final loader = _LifecycleLoader(failFirstFrame: true, frameFailureGate: frameFailure);
    AuthenticatedNetworkImage provider() =>
        AuthenticatedNetworkImage('https://music.test/api/library/albums/replaced-frame/cover', loader: loader);

    final oldLoad = _load(provider());
    await loader.firstFrameRequested.future;
    PaintingBinding.instance.imageCache.evict(provider());
    expect(await _load(provider()), isNull);
    expect(loader.loaded, hasLength(2));

    frameFailure.complete();
    expect(await oldLoad, isA<StateError>());
    await Future<void>.delayed(Duration.zero);
    expect(loader.invalidated, isEmpty);
    expect(PaintingBinding.instance.imageCache.containsKey(provider()), isTrue);
    expect(await _load(provider()), isNull);
    expect(loader.loaded, hasLength(2));
  });
  _thumbnailTests();
}

class _LifecycleLoader implements ArtworkLoader {
  final bool failFirstFrame;
  final bool rejectFirstAdmission;
  final Completer<void>? invalidationGate;
  final Completer<void>? frameFailureGate;
  final firstFrameRequested = Completer<void>();
  final loaded = <ArtworkRequest>[];
  final invalidated = <ArtworkRequest>[];
  int admissions = 0;

  _LifecycleLoader({
    this.failFirstFrame = false,
    this.rejectFirstAdmission = false,
    this.invalidationGate,
    this.frameFailureGate,
  });

  @override
  String get cacheScope => 'provider-lifecycle';

  @override
  Future<Uint8List> load(ArtworkRequest request) async {
    loaded.add(request);
    return _png;
  }

  @override
  Future<T> decode<T>(String scope, Future<T> Function() operation) async {
    final admission = ++admissions;
    if (rejectFirstAdmission && admission == 1) {
      throw const ArtworkLoadException(statusCode: 503);
    }
    final result = await operation();
    if (failFirstFrame && admission == 1 && result is ui.Codec) {
      return _FailedFrameCodec(result, firstFrameRequested, frameFailureGate) as T;
    }
    return result;
  }

  @override
  Future<void> invalidate(ArtworkRequest request) async {
    invalidated.add(request);
    await invalidationGate?.future;
  }

  @override
  Future<void> close() async {}
}

class _FailedFrameCodec implements ui.Codec {
  final ui.Codec codec;
  final Completer<void> requested;
  final Completer<void>? failureGate;

  _FailedFrameCodec(this.codec, this.requested, this.failureGate);

  @override
  int get frameCount => codec.frameCount;

  @override
  int get repetitionCount => codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    requested.complete();
    await failureGate?.future;
    throw StateError('Codec failed to produce its first image frame');
  }

  @override
  void dispose() => codec.dispose();
}

// Widget tests exercise cache ownership and retry behavior, using only fake HTTP.
void _thumbnailTests() {
  testWidgets('thumbnail decoding is bounded and recent entries survive leaving the viewport', (tester) async {
    final client = _Client('none');
    final original = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = original);
    const url = 'https://music.test/api/library/artists/thumbnail/cover?kind=logo';
    final provider = ResizeImage(
      AuthenticatedNetworkImage(url, loader: ArtworkTestLoader(client: client), decodeSize: 64),
      width: 64,
      height: 64,
      policy: ResizeImagePolicy.fit,
    );
    await tester.runAsync(() async => expect(await _load(provider), isNull));
    final key = await provider.obtainKey(ImageConfiguration.empty);
    await tester.pumpWidget(
      ArtworkScope(
        loader: ArtworkTestLoader(client: client),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: ArtworkImage(imageUrl: url, placeholder: SizedBox(), decodeSize: 64, evictWhenUnused: true),
        ),
      ),
    );
    final resized = tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(resized.width, 64);
    expect(resized.height, 64);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(PaintingBinding.instance.imageCache.statusForKey(key).keepAlive, isTrue);
    expect(client.requests, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(PaintingBinding.instance.imageCache.statusForKey(key).keepAlive, isTrue);
    debugNetworkImageHttpClientProvider = original;
  });

  testWidgets('a visible thumbnail retries a transient error without a click', (tester) async {
    final client = _Client('http');
    final original = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = original);
    await tester.pumpWidget(
      ArtworkScope(
        loader: ArtworkTestLoader(client: client),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: ArtworkImage(
            imageUrl: 'https://music.test/api/library/artists/retry/cover?kind=logo',
            placeholder: SizedBox(),
            decodeSize: 64,
            evictWhenUnused: true,
            retryOnError: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.requests, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(client.requests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = original;
  });

  testWidgets('removing a failed thumbnail cancels its retry', (tester) async {
    final client = _Client('http');
    final original = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = original);
    await tester.pumpWidget(
      ArtworkScope(
        loader: ArtworkTestLoader(client: client),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: ArtworkImage(
            imageUrl: 'https://music.test/api/library/artists/leaves/cover?kind=logo',
            placeholder: SizedBox(),
            retryOnError: true,
            evictWhenUnused: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(client.requests, 1);
    debugNetworkImageHttpClientProvider = original;
  });
}

class _Client extends Fake implements HttpClient {
  final String failure;
  int requests = 0;

  _Client(this.failure);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return _Request(
      _Response(requests == 1 && failure == 'http' ? 503 : 200, requests == 1 && failure != 'none' ? [1, 2, 3] : _png),
    );
  }
}

class _Request extends Fake implements HttpClientRequest {
  final _Response response;

  _Request(this.response);

  @override
  HttpHeaders get headers => _Headers();

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Response extends Fake implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> bytes;

  _Response(this.statusCode, this.bytes);

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

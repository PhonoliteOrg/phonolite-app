import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('visible album art recovers after first-frame failure and invalidation', (tester) async {
    final loader = _Loader(firstFrameFailures: 1);
    await tester.pumpWidget(_app(loader));
    await _decode(tester);
    expect(loader.loads, 1);
    expect(loader.invalidations, 1);
    expect(find.byKey(const ValueKey('album-placeholder')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await _decode(tester);
    expect(loader.loads, 2);
    expect(loader.invalidations, 1);
    expect(loader.invalidationsAtLoad, [0, 1]);
    expect(find.byKey(const ValueKey('album-placeholder')), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permanent album art failures stop after two automatic retries', (tester) async {
    final loader = _Loader(firstFrameFailures: 10);
    await tester.pumpWidget(_app(loader));
    await _decode(tester);
    expect(loader.loads, 1);

    await tester.pump(const Duration(seconds: 1));
    await _decode(tester);
    expect(loader.loads, 2);

    await tester.pump(const Duration(seconds: 2));
    await _decode(tester);
    expect(loader.loads, 3);
    expect(loader.invalidations, 3);

    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(loader.loads, 3);
    expect(find.byKey(const ValueKey('album-placeholder')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final status in [401, 403, 404, 410, 413, 422]) {
    testWidgets('terminal HTTP $status album art does not retry', (tester) async {
      final loader = _Loader(statusCode: status);
      await tester.pumpWidget(_app(loader));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(loader.loads, 1);
      expect(find.byKey(const ValueKey('album-placeholder')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('local album art failure does not schedule network-style retries', (tester) async {
    final loader = _Loader(statusCode: 503);
    await tester.pumpWidget(_app(loader, source: '/offline/album/cover.png'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(loader.loads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app(_Loader loader, {String source = 'https://music.test/api/library/albums/album/cover'}) => ArtworkScope(
  loader: loader,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: AlbumArt(
      title: 'Album',
      size: 80,
      imageUrl: source,
      placeholder: const SizedBox(key: ValueKey('album-placeholder')),
    ),
  ),
);

Future<void> _decode(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

class _Loader implements ArtworkLoader {
  final int firstFrameFailures;
  final int? statusCode;
  int loads = 0;
  int invalidations = 0;
  final invalidationsAtLoad = <int>[];

  _Loader({this.firstFrameFailures = 0, this.statusCode});

  @override
  String get cacheScope => 'album-art-retry';

  @override
  Future<Uint8List> load(ArtworkRequest request) async {
    loads++;
    invalidationsAtLoad.add(invalidations);
    if (statusCode != null) {
      throw ArtworkLoadException(statusCode: statusCode);
    }
    return _png;
  }

  @override
  Future<T> decode<T>(String scope, Future<T> Function() operation) async {
    final result = await operation();
    return result is ui.Codec && loads <= firstFrameFailures ? _FailedFirstFrameCodec(result) as T : result;
  }

  @override
  Future<void> invalidate(ArtworkRequest request) async {
    invalidations++;
  }

  @override
  Future<void> close() async {}
}

class _FailedFirstFrameCodec implements ui.Codec {
  final ui.Codec codec;

  _FailedFirstFrameCodec(this.codec);

  @override
  int get frameCount => codec.frameCount;

  @override
  int get repetitionCount => codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async => throw StateError('Invalid image data on first frame');

  @override
  void dispose() => codec.dispose();
}

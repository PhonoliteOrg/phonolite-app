import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/core/artwork_errors.dart';
import 'package:phonolite_app/core/library_helpers.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/widgets/display/album_art.dart';
import 'package:phonolite_app/widgets/display/artist_avatar.dart';

import '../support/widget_test_helpers.dart';

class _ImageClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest();
}

class _ImageRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _ImageHeaders();

  @override
  Future<HttpClientResponse> close() async => _MissingImageResponse();
}

class _ImageHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MissingImageResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 404;

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
}

void main() {
  setUp(configureTestFonts);

  test(
    'missing artwork is info; other failures are warnings, without secrets',
    () {
      final entries = <LogEntry>[];
      final logger = AppLogger()..attach(entries.add);
      final errors = ArtworkErrors(logger: logger);
      final uri = Uri.parse(
        'https://user:password@music.test/cover?kind=logo&token=secret',
      );
      errors.report(
        uri.toString(),
        NetworkImageLoadException(statusCode: 404, uri: uri),
      );
      errors.report(
        uri.toString(),
        NetworkImageLoadException(statusCode: 503, uri: uri),
      );
      errors.report('/missing/image.png', const FileSystemException('missing'));
      expect(entries.map((entry) => entry.level), [
        LogLevel.info,
        LogLevel.warning,
        LogLevel.warning,
      ]);
      expect(entries.first.message, contains('HTTP 404'));
      expect(entries.first.message, contains('kind=logo'));
      expect(entries.first.message, isNot(contains('password')));
      expect(entries.first.message, isNot(contains('secret')));
      expect(entries.last.message, contains('using placeholder'));
    },
  );

  test(
    'duplicate failures are bounded and may log again after five minutes',
    () {
      final entries = <LogEntry>[];
      final logger = AppLogger()..attach(entries.add);
      var now = DateTime.utc(2026, 10, 10);
      final errors = ArtworkErrors(logger: logger, now: () => now);
      final uri = Uri.parse('https://music.test/cover');
      final missing = NetworkImageLoadException(statusCode: 404, uri: uri);
      errors.report(uri.toString(), missing);
      for (var i = 0; i < 100; i++) {
        errors.report(uri.toString(), missing);
      }
      expect(entries, hasLength(1));
      now = now.add(const Duration(minutes: 5));
      errors.report(uri.toString(), missing);
      expect(entries, hasLength(2));
      for (var i = 0; i < 256; i++) {
        errors.report('https://music.test/cover/$i', missing);
      }
      errors.report(uri.toString(), missing);
      expect(entries, hasLength(259));
    },
  );

  test(
    'framework hook handles image HTTP failures and forwards other errors',
    () {
      final original = FlutterError.onError;
      final forwarded = <FlutterErrorDetails>[];
      final logged = <LogEntry>[];
      AppLogger.instance.attach(logged.add, includeHistory: false);
      try {
        FlutterError.onError = forwarded.add;
        installArtworkErrorHandler();
        FlutterError.onError!(
          FlutterErrorDetails(
            library: 'image resource service',
            exception: NetworkImageLoadException(
              statusCode: 404,
              uri: Uri.parse('https://music.test/framework-logo'),
            ),
          ),
        );
        final unrelated = FlutterErrorDetails(
          exception: StateError('UI failed'),
          library: 'widgets library',
        );
        FlutterError.onError!(unrelated);
        final badCodec = FlutterErrorDetails(
          exception: StateError('bad codec'),
          library: 'image resource service',
        );
        FlutterError.onError!(badCodec);
        expect(logged.single.level, LogLevel.info);
        expect(forwarded, [unrelated, badCodec]);
      } finally {
        FlutterError.onError = original;
        AppLogger.instance.detach(logged.add);
      }
    },
  );

  testWidgets('404 artwork renders placeholders and logs once across widgets', (
    tester,
  ) async {
    final original = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => _ImageClient();
    addTearDown(() => debugNetworkImageHttpClientProvider = original);
    final logged = <LogEntry>[];
    AppLogger.instance.attach(logged.add, includeHistory: false);
    addTearDown(() => AppLogger.instance.detach(logged.add));
    const url = 'https://music.test/widget-logo?kind=logo';
    await tester.pumpWidget(
      wrapInTestApp(
        const Row(
          children: [
            ArtistAvatar(name: 'Artist', size: 80, imageUrl: url),
            AlbumArt(title: 'Song', size: 80, imageUrl: url),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(logged.single.level, LogLevel.info);
    debugNetworkImageHttpClientProvider = original;
  });

  testWidgets(
    'prefetch handles a missing image without Flutter error reports',
    (tester) async {
      final original = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => _ImageClient();
      addTearDown(() => debugNetworkImageHttpClientProvider = original);
      final logged = <LogEntry>[];
      AppLogger.instance.attach(logged.add, includeHistory: false);
      addTearDown(() => AppLogger.instance.detach(logged.add));
      await tester.pumpWidget(wrapInTestApp(const SizedBox()));
      // Android allows prefetching; the Windows optimization remains in place.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await precacheImages(tester.element(find.byType(SizedBox).last), [
        'https://music.test/prefetch-logo',
      ]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(logged.single.level, LogLevel.info);
      debugDefaultTargetPlatformOverride = null;
      debugNetworkImageHttpClientProvider = original;
    },
  );
}

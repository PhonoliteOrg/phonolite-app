import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/native_artwork_source.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phonolite/now_playing');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async => calls.add(call));
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native artwork preload sends authenticated sources and an empty replacement window', () async {
    final service = _Service(nativeArtwork: true);
    addTearDown(service.dispose);

    await service.preloadArtwork(const [
      NativeArtworkSource(
        key: 'url:https://server.test/cover',
        url: 'https://server.test/cover',
        token: 'session-token',
        serverPin: 'server-pin',
      ),
      NativeArtworkSource(key: 'file:/local/cover.png', path: '/local/cover.png'),
    ]);
    await service.preloadArtwork(const []);

    expect(calls.map((call) => call.method), ['preloadArtwork', 'preloadArtwork']);
    expect(calls.first.arguments, [
      {
        'artworkKey': 'url:https://server.test/cover',
        'artworkUrl': 'https://server.test/cover',
        'token': 'session-token',
        'serverPin': 'server-pin',
      },
      {'artworkKey': 'file:/local/cover.png', 'artworkPath': '/local/cover.png'},
    ]);
    expect(calls.last.arguments, isEmpty);
  });

  test('platforms using Flutter artwork do not receive native preload commands', () async {
    final service = _Service(nativeArtwork: false);
    addTearDown(service.dispose);

    await service.preloadArtwork(const [NativeArtworkSource(key: 'cover', path: '/cover.png')]);

    expect(calls, isEmpty);
  });
}

class _Service extends NowPlayingPlatformService {
  final bool nativeArtwork;

  _Service({required this.nativeArtwork});

  @override
  bool get loadsArtworkNatively => nativeArtwork;
}

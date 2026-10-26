import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phonolite/now_playing');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NowPlayingPlatformService service;
  late List<MethodCall> publications;

  setUp(() {
    publications = [];
    service = NowPlayingPlatformService();
    messenger.setMockMethodCallHandler(channel, (call) async {
      publications.add(call);

      return null;
    });
  });

  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> incoming(String method, Map<String, dynamic> arguments) async {
    final response = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      response.complete,
    );
    const StandardMethodCodec().decodeEnvelope((await response.future)!);
  }

  test('Windows supports the existing native channel and Flutter-loaded artwork', () {
    if (Platform.isWindows) {
      expect(service.isSupported, isTrue);
      expect(service.loadsArtworkNatively, isFalse);
    }
  });

  test('track metadata, PNG artwork, position and pause updates publish through one channel', () async {
    for (final playing in [true, false]) {
      await service.publish(
        NativeNowPlayingSnapshot(
          epoch: 1,
          trackId: 'local-track',
          title: 'Title é',
          artist: 'Artist',
          album: 'Album',
          duration: const Duration(seconds: 120),
          position: const Duration(milliseconds: 1250),
          isPlaying: playing,
          liked: false,
          artworkKey: 'local-cover',
          artworkBytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
    }
    await service.clearNowPlaying();
    expect(publications.map((call) => call.method), ['setNowPlaying', 'setNowPlaying', 'clearNowPlaying']);
    final payload = publications[1].arguments as Map;
    expect(payload['title'], 'Title é');
    expect(payload['isPlaying'], isFalse);
    expect(payload['position'], 1.25);
    expect(payload['duration'], 120.0);
    expect(payload['artworkBytes'], [1, 2, 3]);
    expect(payload, isNot(contains('token')));
  });

  test('OS buttons and scrubbing decode into the shared application commands', () async {
    final commands = <NativeRemoteCommand>[];
    service.setRemoteCommandHandler((command) async => commands.add(command));

    for (final type in ['play', 'pause', 'next', 'prev']) {
      await incoming('remoteCommand', {'type': type});
    }
    await incoming('remoteCommand', {'type': 'seek', 'position': 12.5});
    await incoming('unrelated', {'type': 'play'});
    expect(commands.map((command) => command.action), [
      NativeRemoteAction.play,
      NativeRemoteAction.pause,
      NativeRemoteAction.next,
      NativeRemoteAction.previous,
      NativeRemoteAction.seek,
    ]);
    expect(commands.last.position, const Duration(milliseconds: 12500));
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('apple platform source contracts', () {
    test('ios preserves audio session now playing and local network setup', () {
      final appDelegate = readProjectFile('ios/Runner/AppDelegate.swift');
      final audioSession = readProjectFile(
        'ios/Runner/AppDelegate+AudioSession.swift',
      );
      final channels = readProjectFile('ios/Runner/AppDelegate+Channels.swift');
      final nowPlaying = readProjectFile(
        'ios/Runner/AppDelegate+NowPlaying.swift',
      );
      final permissions = readProjectFile(
        'ios/Runner/LocalNetworkPermissionManager.swift',
      );
      final infoPlist = readProjectFile('ios/Runner/Info.plist');
      final sceneDelegate = readProjectFile('ios/Runner/SceneDelegate.swift');

      expectContainsAll(appDelegate, const [
        'configureInitialAudioSession()',
        'configureAudioSessionObservers()',
        'configureNowPlayingChannel()',
        'configureCarPlayChannel()',
        'configurePermissionsChannel()',
        'localNetworkPermissions.requestPermission()',
      ]);
      expectContainsAll(audioSession, const [
        '.allowAirPlay',
        '.allowBluetoothA2DP',
        'handleAudioSessionInterruption',
        'handleAudioSessionRouteChange',
        'sendRemoteCommandToFlutter("pause")',
      ]);
      expectContainsAll(channels, const [
        '"phonolite/now_playing"',
        '"phonolite/carplay"',
        'configurePermissionsChannel()',
        'localNetworkPermissions.configureChannel(messenger: messenger)',
      ]);
      expectContainsAll(nowPlaying, const [
        'MPNowPlayingInfoCenter.default().nowPlayingInfo',
        'MPRemoteCommandCenter.shared()',
        '"play"',
        '"pause"',
        '"next"',
        '"prev"',
      ]);
      expectContainsAll(permissions, const [
        '"getLocalNetworkPermission"',
        '"refreshLocalNetworkPermission"',
        '"openAppSettings"',
        'NWListener',
        '_phonolite._tcp',
        '"granted"',
        '"denied"',
      ]);
      expectContainsAll(infoPlist, const [
        'NSLocalNetworkUsageDescription',
        '_phonolite._tcp',
        'CPTemplateApplicationScene',
        '<string>audio</string>',
        'NSAllowsArbitraryLoads',
      ]);
      expectContainsAll(sceneDelegate, const [
        'configureNowPlayingChannel()',
        'configurePermissionsChannel()',
      ]);
    });

    test('carplay scene preserves home library and now playing flows', () {
      final source = readProjectFile('ios/Runner/CarPlaySceneDelegate.swift');

      expectContainsAll(source, const [
        'CPNowPlayingTemplate.shared',
        'title: "Home"',
        'title: "Library"',
        'text: "Artists"',
        'text: "Playlists"',
        'text: "Liked Songs"',
        '"startLibraryShuffle"',
        '"startLikedShuffle"',
        '"startCustomShuffle"',
        'updateNowPlayingButtons(liked: Bool, available: Bool)',
        'updateNowPlayingVisibility(hasTrack: Bool)',
        'sendRemoteCommandToFlutter("toggleLike")',
      ]);
    });

    test('macos preserves app shell and native output device enumeration', () {
      final appDelegate = readProjectFile('macos/Runner/AppDelegate.swift');
      final infoPlist = readProjectFile('macos/Runner/Info.plist');
      final audioHeader = readProjectFile('macos/Runner/phonolite_audio.h');
      final audioSource = readProjectFile('macos/Runner/phonolite_audio.c');
      final windowSource = readProjectFile(
        'macos/Runner/MainFlutterWindow.swift',
      );

      expectContainsAll(appDelegate, const [
        'applicationShouldTerminateAfterLastWindowClosed',
        'applicationSupportsSecureRestorableState',
      ]);
      expectContainsAll(infoPlist, const ['NSAllowsArbitraryLoads']);
      expectContainsAll(windowSource, const [
        'FlutterViewController()',
        'RegisterGeneratedPlugins(registry: flutterViewController)',
      ]);
      expectContainsAll(audioHeader, const [
        'phonolite_audio_get_output_device_count',
        'phonolite_audio_get_output_device_id',
        'phonolite_audio_get_output_device_name',
      ]);
      expectContainsAll(audioSource, const [
        'kAudioQueueProperty_CurrentDevice',
        'phonolite_audio_get_output_device_count',
        'phonolite_audio_get_output_device_id',
        'phonolite_audio_get_output_device_name',
        'AudioObjectGetPropertyData',
      ]);
    });
  });
}

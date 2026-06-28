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
      final offlineStorage = readProjectFile(
        'ios/Runner/AppDelegate+OfflineStorage.swift',
      );
      final nowPlaying = readProjectFile(
        'ios/Runner/AppDelegate+NowPlaying.swift',
      );
      final nowPlayingCoordinator = readProjectFile(
        'ios/Runner/NowPlayingCoordinator.swift',
      );
      final permissions = readProjectFile(
        'ios/Runner/LocalNetworkPermissionManager.swift',
      );
      final localAudioLink = readProjectFile(
        'packages/phonolite_local_audio/ios/Classes/phonolite_local_audio_link.m',
      );
      final project = readProjectFile('ios/Runner.xcodeproj/project.pbxproj');
      final infoPlist = readProjectFile('ios/Runner/Info.plist');
      final sceneDelegate = readProjectFile('ios/Runner/SceneDelegate.swift');

      expectContainsAll(appDelegate, const [
        'configureInitialAudioSession()',
        'configureAudioSessionObservers()',
        'configureNowPlayingChannel()',
        'configureCarPlayChannel()',
        'configurePermissionsChannel()',
        'localNetworkPermissions.requestPermission()',
        'refreshOfflineStorageBackupExclusions()',
        'applicationDidEnterBackground',
      ]);
      expectContainsAll(audioSession, const [
        '.allowAirPlay',
        '.allowBluetoothA2DP',
        'handleAudioSessionInterruption',
        'handleAudioSessionRouteChange',
        'nowPlayingCoordinator.isPlaying',
        'sendRemoteCommandToFlutter("pause")',
      ]);
      expectContainsAll(channels, const [
        '"phonolite/now_playing"',
        '"phonolite/carplay"',
        'configurePermissionsChannel()',
        'localNetworkPermissions.configureChannel(messenger: messenger)',
      ]);
      expectContainsAll(nowPlaying, const [
        'nowPlayingCoordinator.update(',
        'nowPlayingCoordinator.clear(',
        'nowPlayingCoordinator.refreshForCarPlay(',
        'MPRemoteCommandCenter.shared()',
        'nowPlayingCoordinator.isPlaying',
        '"play"',
        '"pause"',
        '"next"',
        '"prev"',
      ]);
      expectContainsAll(nowPlayingCoordinator, const [
        'final class NowPlayingCoordinator',
        'MPNowPlayingInfoCenter.default().nowPlayingInfo',
        'currentArtworkKey',
        'args["artworkKey"]',
        'currentArtwork = nil',
        'fetchArtwork(',
        'artworkKey: normalizedArtworkKey',
        'self.currentArtworkKey == artworkKey',
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
      expectContainsAll(offlineStorage, const [
        'OfflineStorageBackupManager',
        'appendingPathComponent("offline", isDirectory: true)',
        'appendingPathComponent("art", isDirectory: true)',
        'hasPrefix("server_")',
        'values.isExcludedFromBackup = true',
      ]);
      expectContainsAll(localAudioLink, const [
        'phonolite_local_audio_keep_symbols',
        'phonolite_local_audio_open',
        'phonolite_local_audio_read',
        'phonolite_local_audio_seek',
        'phonolite_local_audio_sample_rate',
        'phonolite_local_audio_channels',
        'phonolite_local_audio_duration_ms',
        'phonolite_local_audio_position_ms',
        'phonolite_local_audio_last_error',
        'phonolite_local_audio_close',
      ]);
      expectContainsAll(project, const [
        '-Wl,-exported_symbol,_phonolite_local_audio_open',
        '-Wl,-exported_symbol,_phonolite_local_audio_read',
        '-Wl,-exported_symbol,_phonolite_local_audio_seek',
        '-Wl,-exported_symbol,_phonolite_local_audio_sample_rate',
        '-Wl,-exported_symbol,_phonolite_local_audio_channels',
        '-Wl,-exported_symbol,_phonolite_local_audio_duration_ms',
        '-Wl,-exported_symbol,_phonolite_local_audio_position_ms',
        '-Wl,-exported_symbol,_phonolite_local_audio_last_error',
        '-Wl,-exported_symbol,_phonolite_local_audio_close',
        'NowPlayingCoordinator.swift',
      ]);
      expectContainsAll(infoPlist, const [
        'NSLocalNetworkUsageDescription',
        'NSPhotoLibraryUsageDescription',
        '_phonolite._tcp',
        'CPTemplateApplicationScene',
        '<string>audio</string>',
        'NSAllowsLocalNetworking',
      ]);
      expectContainsAll(sceneDelegate, const [
        'configureNowPlayingChannel()',
        'configurePermissionsChannel()',
        'sceneDidEnterBackground',
        'refreshOfflineStorageBackupExclusions()',
      ]);
    });

    test('carplay scene preserves home library and now playing flows', () {
      final source = readProjectFile('ios/Runner/CarPlaySceneDelegate.swift');
      final controller = readProjectFile('lib/entities/app_controller.dart');

      expectContainsAll(source, const [
        'CPNowPlayingTemplate.shared',
        'buildLoadingTemplate()',
        'title: "Server"',
        'title: "Local"',
        'getCarPlayState',
        'serverAvailable',
        'showRootForCurrentState()',
        'scope: "local"',
        'scope: "server"',
        r'text: "\(sourceName) Library"',
        r'text: "\(sourceName) Playlists"',
        r'text: "\(sourceName) Liked Songs"',
        r'text: "\(sourceName) Shuffle"',
        'carPlaySymbol(named:',
        'withRenderingMode(.alwaysTemplate)',
        '"startShuffle"',
        'updateNowPlayingButtons(liked: Bool, available: Bool)',
        'func updateNowPlayingVisibility(hasTrack _: Bool) {}',
        'sendRemoteCommandToFlutter("toggleLike")',
      ]);
      expect(source, isNot(contains('title: "Listen"')));
      expect(source, isNot(contains('getListenActions')));
      expect(source, isNot(contains('CPBarButton(image:')));
      expect(source, isNot(contains('trailingNavigationBarButtons')));
      expect(source, isNot(contains('nowPlayingButtonVisible')));
      expect(source, isNot(contains('setShowsNowPlayingButton')));
      expect(
        source,
        isNot(contains('setValue(visible, forKey: "showsNowPlayingButton")')),
      );

      expectContainsAll(controller, const [
        "case 'startShuffle':",
        "artistId: args['artistId']?.toString()",
        "albumId: args['albumId']?.toString()",
        "playlistId: args['playlistId']?.toString()",
        "if (kind == 'custom')",
        '_customShuffleSettings.localArtistIds.isEmpty',
        '_customShuffleSettings.localGenres.isEmpty',
        "'artist' => ShuffleMode.artist",
        "'album' => ShuffleMode.album",
        "'custom' => ShuffleMode.custom",
        'await queueLocalShuffle(',
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

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('apple platform source contracts', () {
    test(
      'ios exports every audio FFI binding in every build configuration',
      () {
        final engine = readProjectFile('lib/entities/audio_engine.dart');
        final bindings = engine.substring(
          engine.indexOf('class _CoreAudioBindings'),
          engine.indexOf('typedef _CoreAudioOpenNative'),
        );
        final symbols = RegExp(
          r"'((?:phonolite_audio_)\w+)'",
        ).allMatches(bindings).map((match) => match[1]!).toSet();
        expect(symbols, isNotEmpty);

        final project = readProjectFile('ios/Runner.xcodeproj/project.pbxproj');
        final configurations =
            RegExp(r'/\* (Debug|Release|Profile) \*/ = \{([\s\S]*?)\n\t\t\};')
                .allMatches(project)
                .where(
                  (match) => match[2]!.contains(
                    'PRODUCT_BUNDLE_IDENTIFIER = com.adamuremek.phonolite;',
                  ),
                );
        expect(
          configurations.map((match) => match[1]),
          unorderedEquals(['Debug', 'Release', 'Profile']),
        );
        for (final configuration in configurations) {
          for (final symbol in symbols) {
            expect(
              configuration[2],
              contains('-Wl,-exported_symbol,_$symbol'),
              reason: '${configuration[1]} must expose $symbol to Dart FFI',
            );
          }
        }
      },
    );

    test('ios primes output before starting and reports native failures', () {
      final source = readProjectFile('ios/Runner/phonolite_audio.m');
      final open = source.substring(
        source.indexOf(
          'PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open',
        ),
        source.indexOf('PHONOLITE_EXPORT void phonolite_audio_close'),
      );
      expect(open, isNot(contains('AudioQueueStart(')));
      expect(source, isNot(contains('setPreferredSampleRate:')));
      expect(
        source,
        isNot(contains('AVAudioSessionCategoryOptionAllowAirPlay')),
      );
      expectContainsAll(source, const [
        'if (!phonolite_audio_prepare_session())',
        'player->paused || player->started || atomic_load(&player->in_flight) == 0',
        'return (int32_t)phonolite_audio_start_if_ready(player);',
        'player->output_error = status;',
        'phonolite_audio_flush',
        'AudioQueueReset',
      ]);
      final engine = readProjectFile('lib/entities/audio_engine.dart');
      expectContainsAll(engine, const [
        'Audio output failed:',
        "requestStop(outcome: 'error');",
      ]);
    });

    test(
      'ios artwork fallback is authenticated and invalidates stale requests',
      () {
        final controller = readProjectFile('lib/entities/app_controller.dart');
        final source = readProjectFile(
          'ios/Runner/NowPlayingCoordinator.swift',
        );
        final channels = readProjectFile(
          'ios/Runner/AppDelegate+Channels.swift',
        );
        expectContainsAll(controller, const [
          "if (artworkUrl != null) 'artworkUrl': artworkUrl",
          "if (artworkUrl != null) 'token': token",
          "if (localArtworkPath != null) 'artworkPath': localArtworkPath",
        ]);
        expectContainsAll(source, const [
          'artworkTask?.cancel()',
          'self.artworkGeneration == generation',
          '(200..<300).contains(response.statusCode)',
          'self.artworkLoading = false',
          'URL(fileURLWithPath: localPath)',
          'typedData.data != currentArtworkData',
          'info[MPMediaItemPropertyArtwork] = artwork',
        ]);
        expectContainsAll(channels, const [
          'guard Thread.isMainThread else',
          'DispatchQueue.main.async',
          'nowPlayingCoordinator.isPlaying ? "pause" : "play"',
        ]);
      },
    );

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
        'session.setCategory(.playback, mode: .default, options: [])',
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
        'sendRemoteCommandToFlutter("toggle")',
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
        'args["serverPin"]',
        'final class PinnedArtworkSession',
        'tlsMinimumSupportedProtocolVersion = .TLSv13',
        'phonolite_security_spki(',
        'actual == pin',
        'completionHandler(.cancelAuthenticationChallenge, nil)',
        'completionHandler(nil)',
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
        'CPGridTemplate(',
        'gridButtons: buildSourceButtons(scope: scope)',
        'titleVariants: ["Library"]',
        'titleVariants: ["Playlists"]',
        'titleVariants: ["Liked Songs", "Liked"]',
        'titleVariants: ["Shuffle"]',
        'carPlayIcon(named:',
        'UIImage(named: imageName)',
        '"LucideHeartFilled"',
        'withRenderingMode(.alwaysTemplate)',
        '"startShuffle"',
        'updateNowPlayingButtons(liked: Bool, available: Bool)',
        'func updateNowPlayingVisibility(hasTrack _: Bool) {}',
        'nowPlayingTemplate.setValue(true, forKey: "allowsMiniPlayer")',
        'CPTabBarTemplate(templates: templates)',
        'template.tabTitle = title',
        'self?.refreshNowPlayingUI(force: true)',
        'sendRemoteCommandToFlutter("toggleLike")',
        'PinnedArtworkSession.make(url: url, pin: serverPin)',
        'serverPin: entry.serverPin',
      ]);
      expect(source, isNot(contains('URLSession.shared')));
      expect(source, isNot(contains('title: "Listen"')));
      expect(source, isNot(contains('getListenActions')));
      expect(source, isNot(contains('leadingNavigationBarButtons')));
      expect(source, isNot(contains('trailingNavigationBarButtons')));
      expect(source, isNot(contains('configureNowPlayingShortcut')));
      expect(
        source,
        isNot(contains('setValue(false, forKey: "allowsMiniPlayer")')),
      );
      expect(source, isNot(contains('hasNowPlayingTrack')));
      expect(source, isNot(contains('trailingNavigationBarButtons = []')));
      expect(source, isNot(contains('title: nil')));
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
        'phonolite_audio_flush',
        'phonolite_audio_get_output_device_count',
        'phonolite_audio_get_output_device_id',
        'phonolite_audio_get_output_device_name',
      ]);
      expectContainsAll(audioSource, const [
        'phonolite_audio_flush',
        'AudioQueueReset',
        'kAudioQueueProperty_CurrentDevice',
        'phonolite_audio_get_output_device_count',
        'phonolite_audio_get_output_device_id',
        'phonolite_audio_get_output_device_name',
        'AudioObjectGetPropertyData',
      ]);
    });
  });
}

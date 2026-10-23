import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('apple platform source contracts', () {
    test('ios exports every audio FFI binding in every build configuration', () {
      final bindings = readProjectFile('lib/infrastructure/platform/audio/apple/core_audio_bindings.dart');
      final symbols = RegExp(r"'((?:phonolite_audio_)\w+)'").allMatches(bindings).map((match) => match[1]!).toSet();
      expect(symbols, isNotEmpty);

      final project = readProjectModule('ios/Runner.xcodeproj/project.pbxproj');
      final configurations = RegExp(r'/\* (Debug|Release|Profile) \*/ = \{([\s\S]*?)\n\t\t\};')
          .allMatches(project)
          .where((match) => match[2]!.contains('PRODUCT_BUNDLE_IDENTIFIER = com.adamuremek.phonolite;'));
      expect(configurations.map((match) => match[1]), unorderedEquals(['Debug', 'Release', 'Profile']));
      for (final configuration in configurations) {
        for (final symbol in symbols) {
          expect(
            configuration[2],
            contains('-Wl,-exported_symbol,_$symbol'),
            reason: '${configuration[1]} must expose $symbol to Dart FFI',
          );
        }
      }
    });

    test('ios primes output before starting and reports native failures', () {
      final source = readProjectModule('ios/Runner/Infrastructure/Audio/Native/phonolite_audio.m');
      final open = source.substring(
        source.indexOf('PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open'),
        source.indexOf('PHONOLITE_EXPORT void phonolite_audio_close'),
      );
      expect(open, isNot(contains('AudioQueueStart(')));
      expect(source, isNot(contains('setPreferredSampleRate:')));
      expect(source, isNot(contains('AVAudioSessionCategoryOptionAllowAirPlay')));
      expectContainsAll(source, const [
        'if (!phonolite_audio_prepare_session())',
        'player->paused || player->started || atomic_load(&player->in_flight) == 0',
        'return (int32_t)phonolite_audio_start_if_ready(player);',
        'player->output_error = status;',
        'phonolite_audio_flush',
        'AudioQueueReset',
      ]);
      final engine = readProjectModule('lib/infrastructure/audio/engine/audio_engine.dart');
      expectContainsAll(engine, const ['Audio output failed:', "requestStop(outcome: 'error');"]);
    });

    test('ios artwork fallback is authenticated and invalidates stale requests', () {
      final controller = readProjectModule('lib/application/app/app_controller.dart');
      final artwork = readProjectFiles(const [
        'ios/Runner/Infrastructure/Artwork/NativeArtworkLoader.swift',
        'ios/Runner/Infrastructure/Artwork/NowPlayingArtworkController.swift',
        'ios/Runner/Infrastructure/Media/NowPlayingInfoPublisher.swift',
      ]);
      final host = readProjectModule('ios/Runner/Bootstrap/NativeHost.swift');
      expectContainsAll(controller, const [
        'NativeNowPlayingSnapshot(',
        'artworkUrl: artworkUrl',
        'token: token',
        'artworkPath: localArtworkPath',
      ]);
      final codec = readProjectModule('lib/infrastructure/platform/media/now_playing_codec.dart');
      expectContainsAll(codec, const [
        "if (snapshot.artworkUrl != null)",
        "'artworkUrl': snapshot.artworkUrl",
        "'token': snapshot.token",
        "if (snapshot.artworkPath != null) 'artworkPath': snapshot.artworkPath",
      ]);
      expectContainsAll(artwork, const [
        'task?.cancel()',
        'generation == requestGeneration',
        'source.key == artworkKey',
        '(200..<300).contains(response.statusCode)',
        'isLoading = false',
        'URL(fileURLWithPath: path)',
        'inlineData != current?.data',
        'request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")',
        'url.scheme == "https"',
        'PinnedArtworkSession.make(url: url, pin: serverPin)',
        'info[MPMediaItemPropertyArtwork] = artwork',
      ]);
      expectContainsAll(host, const [
        'guard Thread.isMainThread else',
        'DispatchQueue.main.async',
        'nowPlaying.isPlaying ? .pause : .play',
      ]);
    });

    test('ios preserves audio session now playing and local network setup', () {
      final appDelegate = readProjectModule('ios/Runner/Bootstrap/AppDelegate.swift');
      final host = readProjectModule('ios/Runner/Bootstrap/NativeHost.swift');
      final audioSession = readProjectModule('ios/Runner/Infrastructure/Audio/AudioSessionService.swift');
      final channels = readProjectFiles(const [
        'ios/Runner/Infrastructure/Flutter/NowPlayingChannelAdapter.swift',
        'ios/Runner/Infrastructure/Flutter/CarPlayChannelAdapter.swift',
        'ios/Runner/Infrastructure/Flutter/PermissionsChannelAdapter.swift',
      ]);
      final offlineStorage = readProjectModule('ios/Runner/Data/Storage/Offline/OfflineBackupExclusions.swift');
      final remoteCommands = readProjectModule('ios/Runner/Infrastructure/Media/RemoteCommandService.swift');
      final nativeCommands = readProjectModule('ios/Runner/Data/Models/Playback/NativeRemoteCommand.swift');
      final nowPlaying = readProjectModule('ios/Runner/Infrastructure/Media/NowPlayingCoordinator.swift');
      final publisher = readProjectModule('ios/Runner/Infrastructure/Media/NowPlayingInfoPublisher.swift');
      final nowPlayingCodec = readProjectModule('ios/Runner/Infrastructure/Flutter/NowPlayingCodec.swift');
      final pinning = readProjectModule('ios/Runner/Infrastructure/Security/PinnedArtworkSession.swift');
      final permissions = readProjectFiles(const [
        'ios/Runner/Infrastructure/Flutter/PermissionsChannelAdapter.swift',
        'ios/Runner/Infrastructure/Permissions/LocalNetworkPermissionProbe.swift',
        'ios/Runner/Data/Models/Permissions/LocalNetworkPermissionStatus.swift',
      ]);
      final localAudioLink = readProjectModule(
        'packages/phonolite_local_audio/ios/Classes/phonolite_local_audio_link.m',
      );
      final project = readProjectModule('ios/Runner.xcodeproj/project.pbxproj');
      final infoPlist = readProjectModule('ios/Runner/Info.plist');
      final sceneDelegate = readProjectModule('ios/Runner/Bootstrap/SceneDelegate.swift');

      expectContainsAll(appDelegate, const [
        'configureInitialAudioSession()',
        'configureAudioSessionObservers()',
        'configureNowPlayingChannel()',
        'configureCarPlayChannel()',
        'configurePermissionsChannel()',
        'requestLocalNetworkPermission()',
        'refreshOfflineStorageBackupExclusions()',
        'applicationDidEnterBackground',
      ]);
      final startupSteps = [
        'GeneratedPluginRegistrant.register(with: self)',
        'nativeHost.configureInitialAudioSession()',
        'nativeHost.configureAudioSessionObservers()',
        'super.application(application, didFinishLaunchingWithOptions: launchOptions)',
        'nativeHost.configureNowPlayingChannel()',
        'nativeHost.configureCarPlayChannel()',
        'nativeHost.configurePermissionsChannel()',
        'nativeHost.requestLocalNetworkPermission()',
        'nativeHost.refreshOfflineStorageBackupExclusions()',
      ].map(appDelegate.indexOf).toList();

      expect(startupSteps, everyElement(greaterThanOrEqualTo(0)));
      expect(startupSteps, orderedEquals([...startupSteps]..sort()));
      expectContainsAll(audioSession, const [
        'session.setCategory(.playback, mode: .default, options: [])',
        'handleInterruption',
        'handleRouteChange',
        'isPlaying()',
        'sendRemoteCommand(.pause)',
      ]);
      expectContainsAll(channels, const [
        '"phonolite/now_playing"',
        '"phonolite/carplay"',
        '"phonolite/permissions"',
        'NowPlayingCodec.decode(arguments)',
      ]);
      expectContainsAll(nowPlaying, const [
        'state.apply(update)',
        'artwork.clear()',
        'publisher.clear()',
        'refreshPresentation()',
      ]);
      expectContainsAll(host, const [
        'nowPlaying.update(update)',
        'nowPlaying.clear()',
        'nowPlaying.refreshPresentation()',
      ]);
      expectContainsAll(remoteCommands, const [
        'MPRemoteCommandCenter.shared()',
        'register(commandCenter.togglePlayPauseCommand, action: .toggle)',
        'register(commandCenter.playCommand, action: .play)',
        'register(commandCenter.pauseCommand, action: .pause)',
        'register(commandCenter.nextTrackCommand, action: .next)',
        'register(commandCenter.previousTrackCommand, action: .previous)',
      ]);
      expectContainsAll(nativeCommands, const ['case play', 'case pause', 'case next', 'case previous = "prev"']);
      expectContainsAll(publisher, const ['MPNowPlayingInfoCenter.default().nowPlayingInfo']);
      expectContainsAll(nowPlayingCodec, const [
        'args["artworkKey"]',
        'args["serverPin"]',
        'args["artworkPath"]',
        'FlutterStandardTypedData',
      ]);
      expectContainsAll(pinning, const [
        'final class PinnedArtworkSession',
        'tlsMinimumSupportedProtocolVersion = .TLSv13',
        'phonolite_security_spki(',
        'actual == pin',
        'completionHandler(.cancelAuthenticationChallenge, nil)',
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
        'OfflineBackupExclusions',
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
        'NSAllowsArbitraryLoads',
      ]);
      // These keys override NSAllowsArbitraryLoads and break native artwork
      // from user-selected servers with authenticated self-signed certificates.
      for (final key in const [
        'NSAllowsLocalNetworking',
        'NSAllowsArbitraryLoadsForMedia',
        'NSAllowsArbitraryLoadsInWebContent',
      ]) {
        expect(infoPlist, isNot(contains('<key>$key</key>')));
      }
      expectContainsAll(sceneDelegate, const [
        'configureNowPlayingChannel()',
        'configurePermissionsChannel()',
        'sceneDidEnterBackground',
        'refreshOfflineStorageBackupExclusions()',
      ]);
    });

    test('carplay scene preserves home library and now playing flows', () {
      final source = readProjectFiles(const [
        'ios/Runner/Bootstrap/NativeHost.swift',
        'ios/Runner/Pages/CarPlay/CarPlayRootPage.swift',
        'ios/Runner/Pages/CarPlay/CarPlayNavigationCoordinator.swift',
        'ios/Runner/UI/Shell/CarPlay/CarPlayShell.swift',
        'ios/Runner/UI/Structures/CarPlay/CarPlaySourceGrid.swift',
        'ios/Runner/UI/Structures/CarPlay/CarPlayNowPlayingPresenter.swift',
        'ios/Runner/UI/Shared/CarPlay/CarPlayIconProvider.swift',
        'ios/Runner/Infrastructure/Flutter/CarPlayCodec.swift',
        'ios/Runner/Infrastructure/Artwork/CarPlayArtworkLoader.swift',
      ]);
      final page = readProjectModule('ios/Runner/Pages/CarPlay/CarPlayBrowsePage.swift');
      final frame = readProjectModule('ios/Runner/UI/Structures/CarPlay/CarPlayListFrame.swift');
      final browse = readProjectModule('ios/Runner/Application/Controllers/CarPlay/CarPlayBrowseController.swift');
      final controller = readProjectModule('lib/application/app/app_controller.dart');

      expectContainsAll(source, const [
        'CPNowPlayingTemplate.shared',
        'makeLoadingTemplate()',
        '"Local" : "Server"',
        'getCarPlayState',
        'serverAvailable',
        'scope: .local',
        'scope: .server',
        'CPGridTemplate(',
        'gridButtons: makeButtons(scope: scope, contentStyle: contentStyle)',
        'titleVariants: ["Library"]',
        'titleVariants: ["Playlists"]',
        'titleVariants: ["Liked Songs", "Liked"]',
        'titleVariants: ["Shuffle"]',
        'templateIcon(named:',
        'UIImage(named: imageName)',
        '"LucideHeartFilled"',
        'withRenderingMode(.alwaysTemplate)',
        '"startShuffle"',
        'updateNowPlayingButtons(liked: Bool, available: Bool)',
        '#available(iOS 27.0, *)',
        'template.responds(to: NSSelectorFromString("setAllowsMiniPlayer:"))',
        'template.setValue(true, forKey: "allowsMiniPlayer")',
        'CPTabBarTemplate(templates:',
        'template.tabTitle = title',
        'self?.refreshNowPlaying()',
        'sendRemoteCommand(.toggleLike)',
        'PinnedArtworkSession.make(url: url, pin: serverPin)',
        'serverPin: entry.serverPin',
      ]);
      expectContainsAll(page, const [
        'let template = frame.makeLoadingTemplate()',
        'present(template)',
        'controller.load(request)',
        'frame.update(template, result: result, onSelect: onSelect)',
      ]);
      expectContainsAll(frame, const [
        'template.updateSections([CPListSection(items: items)])',
        'item.isEnabled = entry.enabled',
        'onSelect(entry)',
        'completion()',
      ]);
      expectContainsAll(browse, const ['pendingRequests.removeAll()', 'self.pendingRequests.remove(requestID) != nil']);
      expect(source, isNot(contains('URLSession.shared')));
      expect(source, isNot(contains('title: "Listen"')));
      expect(source, isNot(contains('getListenActions')));
      expect(source, isNot(contains('leadingNavigationBarButtons')));
      expect(source, isNot(contains('trailingNavigationBarButtons')));
      expect(source, isNot(contains('configureNowPlayingShortcut')));
      expect(source, isNot(contains('setValue(false, forKey: "allowsMiniPlayer")')));
      expect(source, isNot(contains('hasNowPlayingTrack')));
      expect(source, isNot(contains('trailingNavigationBarButtons = []')));
      expect(source, isNot(contains('title: nil')));
      expect(source, isNot(contains('nowPlayingButtonVisible')));
      expect(source, isNot(contains('setShowsNowPlayingButton')));
      expect(source, isNot(contains('setValue(visible, forKey: "showsNowPlayingButton")')));

      expectContainsAll(controller, const [
        'VehicleOperation.startShuffle => _carPlayStartShuffle(',
        'artistId: request.artistId',
        'albumId: request.albumId',
        'playlistId: request.playlistId',
        'if (kind == VehicleShuffleKind.custom)',
        '_customShuffleSettings.localArtistIds.isEmpty',
        '_customShuffleSettings.localGenres.isEmpty',
        'VehicleShuffleKind.artist => ShuffleMode.artist',
        'VehicleShuffleKind.album => ShuffleMode.album',
        'VehicleShuffleKind.custom => ShuffleMode.custom',
        "await _host.queueLocalShuffle(",
      ]);
    });

    test('macos preserves app shell and native output device enumeration', () {
      final appDelegate = readProjectModule('macos/Runner/Bootstrap/AppDelegate.swift');
      final infoPlist = readProjectModule('macos/Runner/Info.plist');
      final audioHeader = readProjectModule('macos/Runner/Infrastructure/Audio/Native/phonolite_audio.h');
      final audioSource = readProjectFiles(const [
        'macos/Runner/Infrastructure/Audio/Native/phonolite_audio.c',
        'macos/Runner/Infrastructure/Audio/Native/audio_queue_player.c',
        'macos/Runner/Infrastructure/Audio/Native/audio_output_devices.c',
      ]);
      final windowSource = readProjectModule('macos/Runner/Bootstrap/MainFlutterWindow.swift');

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

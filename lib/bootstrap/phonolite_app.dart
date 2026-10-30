import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/artwork/managed_artwork_loader.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/navigation/desktop_playback_shortcuts.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_viewport.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';
import 'package:phonolite_app/ui/shared/music/artwork/decoded_artwork_preloader.dart';

class PhonoliteApp extends StatefulWidget {
  const PhonoliteApp({super.key});

  @override
  State<PhonoliteApp> createState() => _PhonoliteAppState();
}

class _PhonoliteAppState extends State<PhonoliteApp> {
  late final AppController _controller;
  late final ManagedArtworkLoader _artworkLoader;
  late final DecodedArtworkPreloader _shuffleArtworkPreloader;
  late final AppLifecycleListener _logLifecycle;
  Future<void>? _shutdown;

  @override
  void initState() {
    super.initState();

    _logLifecycle = AppLifecycleListener(onStateChange: (_) => unawaited(AppLogger.instance.flush()));

    const baseUrl = String.fromEnvironment('PHONOLITE_URL', defaultValue: 'https://127.0.0.1:3000/api');
    final connection = ServerConnection(baseUrl: baseUrl);

    _artworkLoader = ManagedArtworkLoader(connection: connection, accountScope: () => _controller.artworkAccountScope);
    _shuffleArtworkPreloader = DecodedArtworkPreloader(loader: _artworkLoader);
    _controller = AppController(connection: connection, shuffleArtworkPreloader: _shuffleArtworkPreloader);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 16 * 1024 * 1024;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_initializeDesktopFeatures());
      }
    });
    unawaited(_initializeController());
  }

  @override
  void dispose() {
    unawaited(_shutdownDesktop());
    _logLifecycle.dispose();
    unawaited(AppUpdatesController.instance.shutdown());
    unawaited(DesktopSettingsController.instance.shutdown());

    unawaited(AppLogger.instance.flush());

    super.dispose();
  }

  Future<void> _initializeController() async {
    try {
      await DownloadSettingsController.instance.initialize();
    } catch (error) {
      AppLogger.warning('Download preferences are unavailable; open Download quality in Settings to retry: $error');
    }

    try {
      await Future.wait([_controller.initialize(), DisplaySettingsController.instance.initialize()]);

      if (!mounted) {
        return;
      }

      await _controller.restoreSession();
    } catch (error, stackTrace) {
      AppLogger.error('Phonolite could not start. Restart the app and check its storage permissions: $error');
      AppLogger.debug('Application startup failure: $stackTrace');
    }
  }

  Future<void> _initializeDesktopFeatures() async {
    await DesktopSettingsController.instance.initialize(beforeQuit: _shutdownDesktop);
    if (mounted && AppUpdatesController.instance.supported) {
      await AppUpdatesController.instance.initialize(onInstall: DesktopSettingsController.instance.quit);
    }
  }

  Future<void> _shutdownDesktop() => _shutdown ??= _closeApplication();

  Future<void> _closeApplication() async {
    final controllerClosed = _controller.close();
    _shuffleArtworkPreloader.dispose();
    await Future.wait([
      controllerClosed,
      _artworkLoader.close(),
      DisplaySettingsController.instance.flush(),
      DownloadSettingsController.instance.flush(),
    ]);
    _controller.connection.close();
    await AppLogger.instance.flush();
  }

  void _togglePlayback() => unawaited(_controller.pause(_controller.playbackState.isPlaying));

  @override
  Widget build(BuildContext context) {
    return ArtworkScope(
      loader: _artworkLoader,
      child: AppScope(
        controller: _controller,
        child: MaterialApp(
          title: 'Phonolite',
          theme: ObsidianTheme.build(),
          themeAnimationStyle: AnimationStyle.noAnimation,
          builder: (context, child) => DesktopPlaybackShortcuts(
            onTogglePlayPause: _togglePlayback,
            child: TooltipVisibility(visible: false, child: ObsidianViewport(child: child ?? const SizedBox.shrink())),
          ),
          home: const HomePage(),
        ),
      ),
    );
  }
}

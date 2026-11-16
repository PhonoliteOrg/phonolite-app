import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/app_settings_controllers.dart';
import 'package:phonolite_app/bootstrap/phonolite_app_shell.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/artwork/managed_artwork_loader.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';
import 'package:phonolite_app/ui/shared/music/artwork/decoded_artwork_preloader.dart';

class PhonoliteApp extends StatefulWidget {
  const PhonoliteApp({super.key});

  @override
  State<PhonoliteApp> createState() => _PhonoliteAppState();
}

class _PhonoliteAppState extends State<PhonoliteApp> {
  final _settings = AppSettingsControllers.shared;
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
    _controller = AppController(
      connection: connection,
      shuffleArtworkPreloader: _shuffleArtworkPreloader,
      downloadSettings: _settings.download,
    );
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
    unawaited(_settings.updates.shutdown());
    unawaited(_settings.desktop.shutdown());

    unawaited(AppLogger.instance.flush());

    super.dispose();
  }

  Future<void> _initializeController() async {
    try {
      await _settings.download.initialize();
    } catch (error) {
      AppLogger.warning('Download preferences are unavailable; open Download quality in Settings to retry: $error');
    }

    try {
      await Future.wait([_controller.initialize(), _settings.display.initialize()]);

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
    await _settings.desktop.initialize(beforeQuit: _shutdownDesktop);
    if (mounted && _settings.updates.supported) {
      await _settings.updates.initialize(
        onPrepare: _settings.desktop.prepareForUpdate,
        onInstall: _settings.desktop.quitForUpdate,
      );
    }
  }

  Future<void> _shutdownDesktop() => _shutdown ??= _closeApplication();

  Future<void> _closeApplication() async {
    final controllerClosed = _controller.close();
    _shuffleArtworkPreloader.dispose();
    await Future.wait([
      controllerClosed,
      _artworkLoader.close(),
      _settings.display.flush(),
      _settings.download.flush(),
    ]);
    _controller.connection.close();
    await AppLogger.instance.flush();
  }

  @override
  Widget build(BuildContext context) {
    return ArtworkScope(
      loader: _artworkLoader,
      child: PhonoliteAppShell(controller: _controller, settings: _settings),
    );
  }
}

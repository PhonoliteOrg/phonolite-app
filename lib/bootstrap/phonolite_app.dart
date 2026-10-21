import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/navigation/desktop_playback_shortcuts.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_viewport.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class PhonoliteApp extends StatefulWidget {
  const PhonoliteApp({super.key});

  @override
  State<PhonoliteApp> createState() => _PhonoliteAppState();
}

class _PhonoliteAppState extends State<PhonoliteApp> {
  late final AppController _controller;
  late final AppLifecycleListener _logLifecycle;

  @override
  void initState() {
    super.initState();

    _logLifecycle = AppLifecycleListener(onStateChange: (_) => unawaited(AppLogger.instance.flush()));

    const baseUrl = String.fromEnvironment('PHONOLITE_URL', defaultValue: 'https://127.0.0.1:3000/api/v1');
    final connection = ServerConnection(baseUrl: baseUrl);

    _controller = AppController(connection: connection);
    unawaited(_initializeController());
  }

  @override
  void dispose() {
    _controller.dispose();
    _logLifecycle.dispose();

    unawaited(AppLogger.instance.flush());

    super.dispose();
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();

      if (!mounted) {
        return;
      }

      await _controller.restoreSession();
    } catch (error, stackTrace) {
      AppLogger.error('Phonolite could not start. Restart the app and check its storage permissions: $error');
      AppLogger.debug('Application startup failure: $stackTrace');
    }
  }

  void _togglePlayback() => unawaited(_controller.pause(_controller.playbackState.isPlaying));

  @override
  Widget build(BuildContext context) {
    return AppScope(
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
    );
  }
}

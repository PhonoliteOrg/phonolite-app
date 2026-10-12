import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/artwork_errors.dart';
import 'entities/app_controller.dart';
import 'entities/app_log.dart';
import 'entities/server_connection.dart';
import 'entities/server_trust.dart';
import 'pages/home_page.dart';
import 'widgets/layouts/app_scope.dart';
import 'widgets/layouts/obsidian_viewport.dart';
import 'widgets/ui/obsidian_theme.dart';
import 'widgets/ui/phonolite_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installServerTrustOverrides();
  installArtworkErrorHandler();
  await AppLogger.instance.initialize();
  PhonoliteIcons.registerLicense();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const PhonoliteApp());
}

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
    _logLifecycle = AppLifecycleListener(
      onStateChange: (_) => unawaited(AppLogger.instance.flush()),
    );
    const baseUrl = String.fromEnvironment(
      'PHONOLITE_URL',
      defaultValue: 'https://127.0.0.1:3000/api/v1',
    );
    final connection = ServerConnection(baseUrl: baseUrl);

    _controller = AppController(connection: connection);
    unawaited(_initializeController());
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (!mounted) return;
    await _controller.restoreSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _logLifecycle.dispose();
    unawaited(AppLogger.instance.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Phonolite',
        theme: ObsidianTheme.build(),
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, child) => TooltipVisibility(
          visible: false,
          child: ObsidianViewport(child: child ?? const SizedBox.shrink()),
        ),
        home: const HomePage(),
      ),
    );
  }
}

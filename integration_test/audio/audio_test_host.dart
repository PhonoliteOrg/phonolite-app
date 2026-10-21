import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/home/home_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_viewport.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

import 'audio_probe.dart';

/// Same controller, session restoration, HomePage and audio implementation as
/// main.dart. A test-only root uses the controller's existing factory seam.
Future<AppController> startAudioTestHost(AudioProbe probe) async {
  installServerTrustOverrides();
  installArtworkErrorHandler();
  await AppLogger.instance.initialize();
  PhonoliteIcons.registerLicense();
  GoogleFonts.config.allowRuntimeFetching = false;
  final controller = AppController(
    connection: ServerConnection(
      baseUrl: const String.fromEnvironment(
        'PHONOLITE_URL',
        defaultValue: 'https://127.0.0.1:3000/api',
      ),
    ),
    audioEngineFactory: probe.createEngine,
  );
  runApp(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: ObsidianTheme.build(),
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, child) => TooltipVisibility(
          visible: false,
          child: ObsidianViewport(child: child ?? const SizedBox.shrink()),
        ),
        home: const HomePage(),
      ),
    ),
  );
  unawaited(() async {
    await controller.initialize();
    await controller.restoreSession();
  }());
  return controller;
}

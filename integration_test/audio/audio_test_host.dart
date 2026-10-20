import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phonolite_app/core/artwork_errors.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/entities/server_trust.dart';
import 'package:phonolite_app/pages/home_page.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_viewport.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

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
        defaultValue: 'https://127.0.0.1:3000/api/v1',
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

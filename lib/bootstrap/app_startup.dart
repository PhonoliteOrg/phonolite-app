import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/bootstrap/phonolite_app.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

Future<void> runPhonolite() async {
  WidgetsFlutterBinding.ensureInitialized();

  installServerTrustOverrides();
  installArtworkErrorHandler();

  await AppLogger.instance.initialize();

  PhonoliteIcons.registerLicense();
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const PhonoliteApp());
}

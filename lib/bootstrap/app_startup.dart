import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/bootstrap/phonolite_app.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/diagnostics/accessibility_trace_binding.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

Future<void> runPhonolite() async {
  if (kDebugMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      BindingBase.debugBindingType() == null) {
    AccessibilityTraceBinding(write: AppLogger.debug);
  }

  WidgetsFlutterBinding.ensureInitialized();

  installServerTrustOverrides();
  installArtworkErrorHandler();

  await AppLogger.instance.initialize();

  if (WidgetsBinding.instance is AccessibilityTraceBinding) {
    AppLogger.debug('Windows accessibility startup tracing enabled; recording structural updates in debug.log.');
  }

  // Reconcile Keychain/secure-storage leftovers before restoration or any manual
  // connection can use them. A saved session remains valid through outages.
  try {
    await const AuthStorage().removeOrphanedCredentials();
  } catch (error, stackTrace) {
    AppLogger.error('Could not check saved server credentials. Restart the app and check its storage permissions.');
    AppLogger.debug('Startup credential cleanup failed: $error\n$stackTrace');
    rethrow;
  }

  PhonoliteIcons.registerLicense();
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const PhonoliteApp());
}

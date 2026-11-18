import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/data/storage/logs/log_files.dart';
import 'package:phonolite_app/application/workflows/restore_storage_access.dart';
import 'package:phonolite_app/bootstrap/app_error_reporting.dart';
import 'package:phonolite_app/bootstrap/phonolite_app.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/diagnostics/accessibility_trace_binding.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/bundled_font_licenses.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_error_handler.dart';
import 'package:phonolite_app/ui/shell/startup_failure_app.dart';

Future<void> runPhonolite() async {
  if (kDebugMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      BindingBase.debugBindingType() == null) {
    AccessibilityTraceBinding(write: AppLogger.debug);
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Reporting first, so the artwork filter installed next runs before it.
  installAppErrorReporting();
  installServerTrustOverrides();
  installArtworkErrorHandler();
  PhonoliteIcons.registerLicense();
  BundledFontLicenses.register();

  await _startApp();
}

Future<void> _startApp() async {
  try {
    await _prepareStorage();
  } on Object catch (error, stackTrace) {
    AppLogger.debug('Startup storage preparation failed: $error\n$stackTrace');
    // Show the failure instead of never reaching runApp, which leaves an empty window.
    runApp(
      StartupFailureApp(
        message: 'Phonolite could not open its saved data. Check its storage permissions, then try again.',
        onRetry: () => unawaited(_startApp()),
      ),
    );

    return;
  }

  runApp(const PhonoliteApp());
}

Future<void> _prepareStorage() async {
  final storageWarnings = await RestoreStorageAccess().restore();

  await AppLogger.instance.initialize(files: LogFiles(preferences: PreferencesCoordinator.shared));

  for (final warning in storageWarnings) {
    AppLogger.warning(warning);
  }

  if (WidgetsBinding.instance is AccessibilityTraceBinding) {
    AppLogger.debug('Windows accessibility startup tracing enabled; recording structural updates in debug.log.');
  }

  // Reconcile Keychain/secure-storage leftovers before restoration or any manual
  // connection can use them. A saved session remains valid through outages.
  try {
    await const AuthStorage().removeOrphanedCredentials();
  } catch (_) {
    AppLogger.error('Could not check saved server credentials. Restart the app and check its storage permissions.');
    rethrow;
  }
}

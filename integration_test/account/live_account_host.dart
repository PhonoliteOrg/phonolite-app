import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phonolite_app/core/artwork_errors.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/listening_stats.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/playback_preferences.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/entities/server_trust.dart';
import 'package:phonolite_app/pages/home_page.dart';
import 'package:phonolite_app/persistence/log_files.dart';
import 'package:phonolite_app/persistence/settings_files.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_viewport.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

/// Actual server mutations, with private client databases and a read-only vault.
/// The caller must verify a user-confirmed disposable username before creating.
class LiveAccountHost {
  LiveAccountHost(this.root, this.storage, this.controller, this.history);
  final Directory root;
  final OfflineLibraryStorage storage;
  final AppController controller;
  final ListeningStatsService history;
  late Future<void> startup;

  static Future<LiveAccountHost> create(AuthCredentials saved) async {
    installServerTrustOverrides();
    installArtworkErrorHandler();
    final root = await Directory.systemTemp.createTemp(
      'phonolite-live-account-test-',
    );
    final files = SettingsFiles(
      directoryProvider: () async => Directory('${root.path}/settings'),
    );
    await AppLogger.instance.initialize(
      files: LogFiles(
        directoryProvider: () async => Directory('${root.path}/logs'),
      ),
    );
    final storage = OfflineLibraryStorage(
      baseDirectory: Directory('${root.path}/offline'),
      settingsStorage: OfflineStorageSettingsStorage(files: files),
    );
    final history = ListeningStatsService(files: files);
    // No synthetic listening history is recorded/uploaded by this account test.
    await history.setEnabled(false);
    final controller = AppController(
      connection: ServerConnection(baseUrl: saved.baseUrl)
        ..setTrust(saved.trust)
        ..setToken(saved.token),
      authStorage: _MemoryAuth(saved),
      offlineStorage: storage,
      customShuffleStorage: CustomShuffleSettingsStorage(files: files),
      playbackPreferencesStorage: PlaybackPreferencesStorage(files: files),
      listeningStatsService: history,
    );
    PhonoliteIcons.registerLicense();
    GoogleFonts.config.allowRuntimeFetching = false;
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
    final host = LiveAccountHost(root, storage, controller, history);
    host.startup = (() async {
      await controller.initialize();
      await controller.restoreSession();
    })();
    unawaited(host.startup);
    return host;
  }

  Future<void> close() async {
    await controller.close();
    await storage.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _MemoryAuth extends AuthStorage {
  _MemoryAuth(this.value);
  AuthCredentials? value;
  @override
  Future<AuthCredentials?> read() async => value;
  @override
  Future<void> write(AuthCredentials credentials) async {
    value = credentials;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

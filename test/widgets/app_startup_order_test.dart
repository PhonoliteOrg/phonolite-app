import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/app_settings_controllers.dart';
import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/bootstrap/phonolite_app.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';
import 'package:phonolite_app/pages/home/home_page.dart';

void main() {
  testWidgets('Home appears at once and the saved session is restored only after the controller and display settings '
      'start', (tester) async {
    final displayRead = Completer<DisplaySettings>();
    final controllerStarted = Completer<void>();
    final settings = AppSettingsControllers(
      display: DisplaySettingsController(storage: _GatedDisplayStorage(displayRead.future)),
      download: DownloadSettingsController(storage: _MemoryDownloadStorage()),
      desktop: DesktopSettingsController(isSupported: () => false),
      updates: AppUpdatesController(isSupported: () => false),
    );
    _StartupController? controller;

    await tester.pumpWidget(
      PhonoliteApp(
        settings: settings,
        createController: ({required connection, required shuffleArtworkPreloader, required downloadSettings}) =>
            controller = _StartupController(connection: connection, started: controllerStarted.future),
      ),
    );
    await tester.pump();

    expect(find.byType(HomePage), findsOneWidget);
    expect(controller!.events, ['initialize']);

    controllerStarted.complete();
    await tester.pump();
    expect(controller!.events, ['initialize']);

    displayRead.complete(const DisplaySettings());
    await tester.pump();
    expect(controller!.events, ['initialize', 'restoreSession']);
    expect(find.byType(HomePage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _StartupController extends AppController {
  final Future<void> started;
  final events = <String>[];

  _StartupController({required super.connection, required this.started});

  @override
  Future<void> initialize() {
    events.add('initialize');

    return started;
  }

  @override
  Future<void> restoreSession() async => events.add('restoreSession');
}

class _GatedDisplayStorage extends DisplaySettingsStorage {
  final Future<DisplaySettings> stored;

  _GatedDisplayStorage(this.stored);

  @override
  Future<DisplaySettings> read() => stored;

  @override
  Future<void> write(DisplaySettings settings) async {}
}

class _MemoryDownloadStorage extends DownloadSettingsStorage {
  @override
  Future<DownloadSettings> read() async => const DownloadSettings();

  @override
  Future<void> write(DownloadSettings settings) async {}
}

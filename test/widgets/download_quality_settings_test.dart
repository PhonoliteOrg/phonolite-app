import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/settings/download_quality_page.dart';
import 'package:phonolite_app/ui/features/settings/sections/local_storage_settings_section.dart';
import 'package:phonolite_app/ui/features/settings/widgets/download_quality_selection.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('quality choices remain usable at width $width', (tester) async {
      final storage = _MemoryStorage();
      final controller = DownloadSettingsController(storage: storage);
      await controller.initialize();
      await _pump(tester, DownloadQualityPage(controller: controller), controller, width: width);

      expect(find.byType(Radio<DownloadQuality>), findsNWidgets(5));
      expect(find.text('High · Recommended'), findsOneWidget);
      expect(find.text('128 kbps · ~58 MB/hour'), findsOneWidget);
      final choice = find.byKey(const ValueKey('download-quality-opus_64'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();

      expect(storage.saved.quality, DownloadQuality.spaceSaver);
      expect(
        tester.widget<RadioGroup<DownloadQuality>>(find.byType(RadioGroup<DownloadQuality>)).groupValue,
        DownloadQuality.spaceSaver,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard arrows choose the next quality in the radio group', (tester) async {
    final storage = _MemoryStorage();
    final controller = DownloadSettingsController(storage: storage);
    await controller.initialize();
    await _pump(tester, DownloadQualityPage(controller: controller), controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(storage.saved.quality, DownloadQuality.veryHigh);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Local Storage tile opens the page and reflects its saved selection on return', (tester) async {
    final controller = DownloadSettingsController(storage: _MemoryStorage());
    final app = _StorageApp();
    addTearDown(app.connection.close);
    await controller.initialize();
    await _pump(
      tester,
      Builder(
        builder: (context) => SingleChildScrollView(
          child: LocalStorageSettingsSection(
            controller: app,
            downloadSettings: controller,
            onDownloadQuality: () => Navigator.of(context).push(DownloadQualityPage.route(controller: controller)),
          ),
        ),
      ),
      controller,
    );

    await tester.tap(find.byKey(const ValueKey('download-quality-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadQualityPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('download-quality-opus_96')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BACK TO SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.byType(DownloadQualityPage), findsNothing);
    expect(find.text('Standard · 96 kbps · ~43 MB/hour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save restores the selected row and reports the problem', (tester) async {
    final storage = _MemoryStorage();
    final controller = DownloadSettingsController(storage: storage);
    await controller.initialize();
    storage.failWrite = true;
    await _pump(tester, DownloadQualityPage(controller: controller), controller);

    await tester.tap(find.byKey(const ValueKey('download-quality-opus_64')));
    await tester.pumpAndSettle();
    expect(controller.settings.quality, DownloadQuality.high);
    expect(find.textContaining('Could not save download settings'), findsOneWidget);
    expect(
      tester.widget<DownloadQualitySelection>(find.byType(DownloadQualitySelection)).quality,
      DownloadQuality.high,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  DownloadSettingsController controller, {
  double width = 390,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(wrapInTestApp(child));
  await tester.pumpAndSettle();
  final layoutError = tester.takeException();
  expect(layoutError, isNull, reason: layoutError is FlutterError ? layoutError.toStringDeep() : null);
}

class _MemoryStorage extends DownloadSettingsStorage {
  DownloadSettings saved = const DownloadSettings(quality: DownloadQuality.high);
  bool failWrite = false;

  @override
  Future<DownloadSettings> read() async => saved;

  @override
  Future<void> write(DownloadSettings settings) async {
    if (failWrite) throw StateError('Storage is full');

    saved = settings;
  }
}

class _StorageApp extends Fake implements AppController {
  @override
  final connection = ServerConnection(
    baseUrl: 'https://download-settings.test/api',
    client: MockClient((_) async => throw StateError('Settings must not make server requests')),
  );

  @override
  OfflineStorageLocations? get offlineStorageLocations => null;

  @override
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream => const Stream.empty();
}

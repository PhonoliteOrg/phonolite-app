import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late SettingsFiles files;
  late DownloadSettingsStorage storage;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phonolite-download-settings-');
    files = SettingsFiles(directoryProvider: () async => temporary);
    storage = DownloadSettingsStorage(files: files);
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('fresh installations use High and existing installations retain Original', () async {
    expect((await storage.read()).quality, DownloadQuality.high);
    await (await files.resolve('download_settings.json')).delete();
    await (await files.resolve('playback_prefs.json')).writeAsString('{}');
    expect((await storage.read()).quality, DownloadQuality.original);
  });

  test('an existing offline library retains Original without other preference files', () async {
    await Directory('${temporary.path}/offline').create();
    expect((await storage.read()).quality, DownloadQuality.original);
  });

  test('every profile survives saving and managed iOS storage-path normalization', () async {
    final managed = OfflineStorageSettingsStorage(files: files, usesManagedStoragePaths: () => true);

    for (final quality in DownloadQuality.values) {
      await storage.write(DownloadSettings(quality: quality));
      await managed.write(
        const OfflineStorageSettings(metadataDirectory: '/old/metadata', downloadsDirectory: '/old/audio'),
      );
      await managed.read();
      expect((await storage.read()).quality, quality);
    }
  });

  test('malformed and unknown settings recover to Original', () async {
    final file = await files.resolve('download_settings.json');

    for (final content in ['{broken', '[]', 'null', '{}', '{"quality":"opus_9000"}']) {
      await file.writeAsString(content);
      expect((await storage.read()).quality, DownloadQuality.original, reason: content);
    }
  });

  test('initialization persists the default before other installation markers appear', () async {
    final controller = DownloadSettingsController(storage: storage);
    addTearDown(controller.dispose);
    await controller.initialize();
    await (await files.resolve('playback_prefs.json')).writeAsString('{}');
    expect((await storage.read()).quality, DownloadQuality.high);
  });

  test('rapid choices save in order and flush waits for the latest preference', () async {
    final controlled = _ControlledStorage();
    final controller = DownloadSettingsController(storage: controlled);
    addTearDown(controller.dispose);
    await controller.initialize();
    controlled.gate = Completer<void>();

    final first = controller.setQuality(DownloadQuality.spaceSaver);
    final second = controller.setQuality(DownloadQuality.veryHigh);
    expect(controller.settings.quality, DownloadQuality.veryHigh);
    expect(controller.saving, isTrue);
    var flushed = false;
    final flush = controller.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    controlled.gate!.complete();
    await Future.wait([first, second, flush]);

    expect(controlled.saved.quality, DownloadQuality.veryHigh);
    expect(controller.saving, isFalse);
  });

  test('save failure restores the last saved choice and a later choice can recover', () async {
    final controlled = _ControlledStorage();
    final controller = DownloadSettingsController(storage: controlled);
    addTearDown(controller.dispose);
    await controller.initialize();
    controlled.failWrite = true;
    await controller.setQuality(DownloadQuality.spaceSaver);
    expect(controller.settings.quality, DownloadQuality.original);
    expect(controller.error, contains('Could not save'));

    controlled.failWrite = false;
    await controller.setQuality(DownloadQuality.standard);
    expect(controller.settings.quality, DownloadQuality.standard);
    expect(controller.error, isNull);
  });

  test('a readable saved preference can load when later writes are unavailable', () async {
    final controlled = _ControlledStorage()
      ..saved = const DownloadSettings(quality: DownloadQuality.standard)
      ..failWrite = true;
    final controller = DownloadSettingsController(storage: controlled);
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.ready, isTrue);
    expect(controller.settings.quality, DownloadQuality.standard);
    expect(controller.error, isNull);
  });

  test('unreadable preferences block initialization and can be retried', () async {
    final controlled = _ControlledStorage()..failRead = true;
    final controller = DownloadSettingsController(storage: controlled);
    addTearDown(controller.dispose);
    await expectLater(controller.initialize(), throwsA(isA<FileSystemException>()));
    expect(controller.ready, isFalse);
    await controller.flush();

    controlled.failRead = false;
    await controller.retryInitialization();
    expect(controller.ready, isTrue);
    expect(controller.error, isNull);
  });
}

class _ControlledStorage extends DownloadSettingsStorage {
  DownloadSettings saved = const DownloadSettings();
  Completer<void>? gate;
  bool failWrite = false;
  bool failRead = false;

  @override
  Future<DownloadSettings> read() async {
    if (failRead) throw const FileSystemException('read denied');

    return saved;
  }

  @override
  Future<void> write(DownloadSettings settings) async {
    await gate?.future;
    if (failWrite) throw const FileSystemException('write denied');

    saved = settings;
  }
}

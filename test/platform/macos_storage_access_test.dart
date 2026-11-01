import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/storage_path_controller.dart';
import 'package:phonolite_app/application/workflows/restore_storage_access.dart';
import 'package:phonolite_app/data/storage/preferences/log_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';
import 'package:phonolite_app/infrastructure/platform/files/macos_directory_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('phonolite/storage_access');
  const access = MacosDirectoryAccess(channel: channel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('restoration keeps resolved paths and unavailable grants distinct', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'restoreDirectories');

      return {
        'paths': {'/old é': '/new é'},
        'unavailable': ['/disconnected'],
      };
    });

    final restored = await access.restore();

    expect(restored.resolve('/old é'), '/new é');
    expect(restored.resolve('/unchanged'), '/unchanged');
    expect(restored.resolve(null), isNull);
    expect(restored.unavailable, {'/disconnected'});
  });

  test('other platforms never invoke the Mac storage channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    messenger.setMockMethodCallHandler(channel, (_) async => fail('Unexpected Mac channel call'));

    expect((await access.restore()).paths, isEmpty);
    expect(await const RestoreStorageAccess().restore(), isEmpty);
  });

  test('folder selection preserves cancellation and native errors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'selectDirectory');
      expect(call.arguments, '/Music é');

      return null;
    });

    expect(await access.selectDirectory('/Music é'), isNull);

    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'access_failed', message: 'Permission denied');
    });

    await expectLater(access.selectDirectory('/Music é'), throwsA(isA<PlatformException>()));
  });

  test('a pending chooser prevents saving and cancellation never saves', () async {
    final choice = Completer<String?>();
    messenger.setMockMethodCallHandler(channel, (_) => choice.future);
    final saved = <String?>[];
    final controller = StoragePathController((path) async => saved.add(path), directoryAccess: access);
    addTearDown(controller.dispose);

    final pending = controller.chooseDirectory('/current');
    await Future<void>.delayed(Duration.zero);

    expect(controller.requiresDirectoryPicker, isTrue);
    expect(controller.busy, isTrue);
    expect(await controller.save('/typed'), isFalse);
    choice.complete(null);

    expect(await pending, isNull);
    expect(controller.busy, isFalse);
    expect(saved, isEmpty);
  });

  test('a selected folder passes unchanged through the existing storage workflow', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => '/Music é/Albums');
    String? saved;
    final controller = StoragePathController((path) async => saved = path);
    addTearDown(controller.dispose);

    final selected = await controller.chooseDirectory('/current');

    expect(await controller.save(selected!), isTrue);
    expect(saved, '/Music é/Albums');
  });

  test('startup follows moved bookmarks before opening storage', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-bookmarks-');
    addTearDown(() => directory.delete(recursive: true));
    final files = SettingsFiles(directoryProvider: () async => directory);
    final logs = LogStorageSettingsStorage(files: files, usesManagedStoragePaths: () => false);
    final offline = OfflineStorageSettingsStorage(files: files, usesManagedStoragePaths: () => false);
    await logs.write('/old/logs');
    await offline.write(const OfflineStorageSettings(metadataDirectory: '/old/db', downloadsDirectory: '/old/audio'));
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'paths': {'/old/logs': '/new/logs', '/old/db': '/new/db', '/old/audio': '/new/audio'},
        'unavailable': <String>[],
      },
    );

    expect(await RestoreStorageAccess(logs: logs, offline: offline).restore(), isEmpty);
    expect(await logs.read(), '/new/logs');
    final restored = await offline.read();
    expect(restored.metadataDirectory, '/new/db');
    expect(restored.downloadsDirectory, '/new/audio');
  });

  test('unavailable logs fall back while offline library locations remain recoverable', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-bookmarks-');
    addTearDown(() => directory.delete(recursive: true));
    final files = SettingsFiles(directoryProvider: () async => directory);
    final logs = LogStorageSettingsStorage(files: files, usesManagedStoragePaths: () => false);
    final offline = OfflineStorageSettingsStorage(files: files, usesManagedStoragePaths: () => false);
    await logs.write('/volume/logs');
    await offline.write(const OfflineStorageSettings(downloadsDirectory: '/volume/audio'));
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'paths': <String, String>{},
        'unavailable': ['/volume/logs', '/volume/audio'],
      },
    );

    expect(await RestoreStorageAccess(logs: logs, offline: offline).restore(), hasLength(2));
    expect(await logs.read(), isNull);
    expect((await offline.read()).downloadsDirectory, '/volume/audio');
  });
}

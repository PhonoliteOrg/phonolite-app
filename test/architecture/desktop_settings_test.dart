import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/desktop_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/storage/preferences/desktop_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late DesktopSettingsStorage storage;
  late _Platform platform;
  late DesktopSettingsController controller;
  late List<String> events;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phonolite-desktop-settings-');
    storage = DesktopSettingsStorage(files: SettingsFiles(directoryProvider: () async => temporary));
    events = [];
    platform = _Platform(events);
    controller = DesktopSettingsController(storage: storage, platform: platform, isSupported: () => true);
  });

  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> initialize() => controller.initialize(beforeQuit: () async => events.add('cleanup'));

  test('fresh and malformed settings enable both desktop features', () async {
    expect((await storage.read()).toJson(), {'launchAtStartup': true, 'runInBackground': true});
    final file = File('${temporary.path}/desktop_settings.json');
    await file.writeAsString('{broken');
    expect((await storage.read()).toJson(), {'launchAtStartup': true, 'runInBackground': true});
    await file.writeAsString('{"launchAtStartup": "false", "runInBackground": false}');
    expect((await storage.read()).toJson(), {'launchAtStartup': true, 'runInBackground': false});
  });

  test('initialization applies defaults once; close hides without shutdown', () async {
    await Future.wait([initialize(), initialize()]);
    expect(events, ['initialize', 'background:true', 'startup:true']);
    await platform.onClose!();
    expect(events.last, 'hide');
    expect(events, isNot(contains('cleanup')));
    expect(controller.error, isNull);
  });

  test('switches persist independently and remain off after restart', () async {
    await initialize();
    await controller.setLaunchAtStartup(false);
    expect(controller.settings.runInBackground, isTrue);
    await controller.setRunInBackground(false);
    expect((await storage.read()).toJson(), {'launchAtStartup': false, 'runInBackground': false});

    final restoredEvents = <String>[];
    final restored = DesktopSettingsController(
      storage: storage,
      platform: _Platform(restoredEvents),
      isSupported: () => true,
    );
    await restored.initialize(beforeQuit: () async {});
    expect(restoredEvents, ['initialize', 'background:false', 'startup:false']);
    await restored.shutdown();
    restored.dispose();

    await controller.closeWindow();
    expect(events.sublist(events.length - 2), ['cleanup', 'quit']);
  });

  test('Quit bypasses background mode and waits for cleanup exactly once', () async {
    final cleanup = Completer<void>();
    await controller.initialize(
      beforeQuit: () {
        events.add('cleanup');

        return cleanup.future;
      },
    );
    final first = platform.onQuit!();
    final second = controller.quit();
    expect(events.last, 'cleanup');
    expect(events, isNot(contains('quit')));
    cleanup.complete();
    await Future.wait([first, second]);
    expect(events.where((event) => event == 'cleanup'), hasLength(1));
    expect(events.where((event) => event == 'quit'), hasLength(1));
  });

  test('a failed startup registration does not stop background mode', () async {
    platform.failStartup = true;
    await initialize();
    expect(controller.error, contains('Launch at startup'));
    await controller.closeWindow();
    expect(events.last, 'hide');
  });

  test('a failed tray setup keeps the window closable instead of hiding it', () async {
    platform.failBackground = true;
    await initialize();
    expect(controller.error, contains('Background mode'));
    await controller.closeWindow();
    expect(events.sublist(events.length - 2), ['cleanup', 'quit']);
    expect(events, isNot(contains('hide')));
  });

  test('persistence failure rolls back the OS setting and reports the failure', () async {
    controller.dispose();
    controller = DesktopSettingsController(storage: _FailedWriteStorage(), platform: platform, isSupported: () => true);
    await initialize();
    await controller.setLaunchAtStartup(false);
    expect(controller.settings.launchAtStartup, isTrue);
    expect(events.sublist(events.length - 2), ['startup:false', 'startup:true']);
    expect(controller.error, contains('Could not save'));
    expect(controller.saving, isFalse);
  });

  test('mobile and web hosts never read preferences or call desktop plugins', () async {
    controller.dispose();
    controller = DesktopSettingsController(
      storage: _UnsupportedStorage(),
      platform: platform,
      isSupported: () => false,
    );
    await initialize();
    await controller.setRunInBackground(false);
    await controller.setLaunchAtStartup(false);
    expect(events, isEmpty);
    expect(controller.supported, isFalse);
  });
}

class _Platform implements DesktopLifecyclePlatform {
  final List<String> events;
  Future<void> Function()? onClose;
  Future<void> Function()? onQuit;
  bool failStartup = false;
  bool failBackground = false;

  _Platform(this.events);

  @override
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit}) async {
    this.onClose = onClose;
    this.onQuit = onQuit;
    events.add('initialize');
  }

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    events.add('startup:$enabled');
    if (failStartup) {
      throw StateError('Login registration denied');
    }
  }

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {
    events.add('background:$enabled');
    if (failBackground) {
      throw StateError('Tray unavailable');
    }
  }

  @override
  Future<void> hide() async => events.add('hide');
  @override
  Future<void> show() async => events.add('show');
  @override
  Future<void> quit() async => events.add('quit');
  @override
  Future<void> dispose() async => events.add('dispose');
}

class _FailedWriteStorage extends DesktopSettingsStorage {
  @override
  Future<DesktopSettings> read() async => const DesktopSettings();
  @override
  Future<void> write(DesktopSettings settings) async => throw const FileSystemException('Read-only settings');
}

class _UnsupportedStorage extends DesktopSettingsStorage {
  @override
  Future<DesktopSettings> read() async => throw StateError('Unsupported host accessed storage');
}

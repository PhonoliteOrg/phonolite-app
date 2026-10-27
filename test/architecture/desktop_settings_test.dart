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

  test('rapid edits update immediately and serialize platform changes and persistence', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final first = controller.setLaunchAtStartup(false);
    final second = controller.setRunInBackground(false);
    final third = controller.setLaunchAtStartup(true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.settings.launchAtStartup, isTrue);
    expect(controller.settings.runInBackground, isFalse);
    expect(controller.saving, isTrue);
    expect(delayed.started, hasLength(1));
    delayed.releaseNext();
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(delayed.started, hasLength(2));
    expect(controller.saving, isTrue);
    delayed.releaseNext();
    await second;
    await Future<void>.delayed(Duration.zero);

    expect(delayed.started, hasLength(3));
    delayed.releaseNext();
    await third;

    expect(delayed.saved.toJson(), {'launchAtStartup': true, 'runInBackground': false});
    expect(platform.startupEnabled, isTrue);
    expect(platform.backgroundEnabled, isFalse);
    expect(controller.saving, isFalse);
    expect(delayed.maximumConcurrentWrites, 1);
  });

  test('a newer snapshot reapplies an older failed setting before it is persisted', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final first = controller.setLaunchAtStartup(false);
    final second = controller.setRunInBackground(false);
    await Future<void>.delayed(Duration.zero);
    delayed.releaseNext(fail: true);
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(controller.settings.launchAtStartup, isFalse);
    expect(controller.settings.runInBackground, isFalse);
    expect(events.where((event) => event == 'startup:false'), hasLength(2));
    expect(platform.startupEnabled, isFalse);
    delayed.releaseNext();
    await second;

    expect(delayed.saved.toJson(), {'launchAtStartup': false, 'runInBackground': false});
    expect(platform.backgroundEnabled, isFalse);
    expect(controller.error, isNull);
  });

  test('a latest failure rolls back only to the last successful settings and platform state', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final first = controller.setLaunchAtStartup(false);
    final second = controller.setRunInBackground(false);
    await Future<void>.delayed(Duration.zero);
    delayed.releaseNext();
    await first;
    await Future<void>.delayed(Duration.zero);
    delayed.releaseNext(fail: true);
    await second;

    expect(controller.settings.toJson(), {'launchAtStartup': false, 'runInBackground': true});
    expect(delayed.saved.toJson(), controller.settings.toJson());
    expect(platform.startupEnabled, isFalse);
    expect(platform.backgroundEnabled, isTrue);
    expect(controller.error, contains('Could not save'));
    expect(controller.saving, isFalse);
  });

  test('quit drains accepted writes before cleanup and refuses new changes', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final save = controller.setLaunchAtStartup(false);
    await Future<void>.delayed(Duration.zero);
    final quitting = controller.quit();
    await controller.setRunInBackground(false);

    expect(events, isNot(contains('cleanup')));
    expect(events, isNot(contains('quit')));
    expect(controller.settings.runInBackground, isTrue);
    delayed.releaseNext();
    await Future.wait([save, quitting]);

    expect(delayed.saved.launchAtStartup, isFalse);
    expect(events.sublist(events.length - 2), ['cleanup', 'quit']);
  });

  test('shutdown drains accepted writes before retiring the platform', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final save = controller.setRunInBackground(false);
    await Future<void>.delayed(Duration.zero);
    final shutdown = controller.shutdown();
    await controller.setLaunchAtStartup(false);

    expect(controller.ready, isFalse);
    expect(events, isNot(contains('dispose')));
    delayed.releaseNext();
    await Future.wait([save, shutdown]);

    expect(delayed.saved.runInBackground, isFalse);
    expect(delayed.saved.launchAtStartup, isTrue);
    expect(events.last, 'dispose');
  });

  test('closing during a pending background change uses the final applied mode', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    controller.dispose();
    controller = DesktopSettingsController(storage: delayed, platform: platform, isSupported: () => true);
    await initialize();

    final save = controller.setRunInBackground(false);
    await Future<void>.delayed(Duration.zero);
    final closing = controller.closeWindow();

    expect(events, isNot(contains('hide')));
    expect(events, isNot(contains('quit')));
    delayed.releaseNext();
    await Future.wait([save, closing]);

    expect(events.sublist(events.length - 2), ['cleanup', 'quit']);
    expect(events, isNot(contains('hide')));
  });

  test('disposing during a save suppresses late notifications and new mutations', () async {
    final delayed = _QueuedStorage();
    addTearDown(delayed.releaseAll);
    final disposed = DesktopSettingsController(storage: delayed, platform: _Platform([]), isSupported: () => true);
    await disposed.initialize(beforeQuit: () async {});
    var notifications = 0;
    disposed.addListener(() => notifications++);

    final save = disposed.setLaunchAtStartup(false);
    await Future<void>.delayed(Duration.zero);
    disposed.dispose();
    final acceptedNotifications = notifications;
    await disposed.setRunInBackground(false);
    delayed.releaseNext();
    await save;
    await disposed.shutdown();

    expect(notifications, acceptedNotifications);
    expect(delayed.started, hasLength(1));
  });
}

class _Platform implements DesktopLifecyclePlatform {
  final List<String> events;
  Future<void> Function()? onClose;
  Future<void> Function()? onQuit;
  bool failStartup = false;
  bool failBackground = false;
  bool startupEnabled = false;
  bool backgroundEnabled = false;

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

    startupEnabled = enabled;
  }

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {
    events.add('background:$enabled');
    if (failBackground) {
      throw StateError('Tray unavailable');
    }

    backgroundEnabled = enabled;
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

class _QueuedStorage extends DesktopSettingsStorage {
  final List<DesktopSettings> started = [];
  final List<Completer<bool>> _pending = [];
  DesktopSettings saved = const DesktopSettings();
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  bool _released = false;

  @override
  Future<DesktopSettings> read() async => saved;

  @override
  Future<void> write(DesktopSettings settings) async {
    started.add(settings);
    _activeWrites++;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }

    try {
      if (!_released) {
        final completion = Completer<bool>();
        _pending.add(completion);

        if (await completion.future) {
          throw const FileSystemException('Settings write failed');
        }
      }

      saved = settings;
    } finally {
      _activeWrites--;
    }
  }

  void releaseNext({bool fail = false}) => _pending.removeAt(0).complete(fail);

  void releaseAll() {
    _released = true;

    for (final completion in _pending) {
      completion.complete(false);
    }

    _pending.clear();
  }
}

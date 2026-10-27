import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late DisplaySettingsStorage storage;
  late DisplaySettingsController controller;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phonolite-display-settings-');
    storage = DisplaySettingsStorage(files: SettingsFiles(directoryProvider: () async => temporary));
    controller = DisplaySettingsController(storage: storage);
  });

  tearDown(() async {
    await controller.flush();
    controller.dispose();
    await temporary.delete(recursive: true);
  });

  test('missing and malformed preferences preserve local-first defaults', () async {
    const defaults = {'libraryLocalFirst': true, 'playlistsLocalFirst': true, 'likesLocalFirst': true};

    expect((await storage.read()).toJson(), defaults);

    final file = File('${temporary.path}/display_settings.json');

    for (final content in ['{broken', '[]', 'null']) {
      await file.writeAsString(content);
      expect((await storage.read()).toJson(), defaults);
    }

    await file.writeAsString('{"libraryLocalFirst":"false","playlistsLocalFirst":false,"likesLocalFirst":0}');

    expect((await storage.read()).toJson(), {
      'libraryLocalFirst': true,
      'playlistsLocalFirst': false,
      'likesLocalFirst': true,
    });
  });

  test('each page preference persists independently and restores on restart', () async {
    await controller.initialize();
    await controller.setLibraryLocalFirst(false);

    expect(controller.settings.toJson(), {
      'libraryLocalFirst': false,
      'playlistsLocalFirst': true,
      'likesLocalFirst': true,
    });

    await controller.setPlaylistsLocalFirst(false);
    await controller.setLikesLocalFirst(false);
    await controller.setPlaylistsLocalFirst(true);
    await controller.flush();

    final restored = DisplaySettingsController(storage: storage);
    addTearDown(restored.dispose);
    await restored.initialize();

    expect(restored.ready, isTrue);
    expect(restored.settings.toJson(), {
      'libraryLocalFirst': false,
      'playlistsLocalFirst': true,
      'likesLocalFirst': false,
    });
    expect((await storage.read()).toJson(), restored.settings.toJson());
  });

  test('initialization runs once and premature edits cannot overwrite stored values', () async {
    final delayed = _ControlledStorage(
      initial: const DisplaySettings(libraryLocalFirst: false, likesLocalFirst: false),
      delayRead: true,
    );
    controller.dispose();
    controller = DisplaySettingsController(storage: delayed);

    final first = controller.initialize();
    final second = controller.initialize();

    expect(controller.ready, isFalse);
    await controller.setLibraryLocalFirst(true);
    delayed.finishRead();
    await Future.wait([first, second]);

    expect(delayed.reads, 1);
    expect(delayed.writes, 0);
    expect(controller.ready, isTrue);
    expect(controller.settings.libraryLocalFirst, isFalse);
    expect(controller.settings.likesLocalFirst, isFalse);
  });

  test('a failed save preserves the current setting and a later edit can recover', () async {
    final controlled = _ControlledStorage()..failWrite = true;
    controller.dispose();
    controller = DisplaySettingsController(storage: controlled);
    await controller.initialize();
    await controller.setLibraryLocalFirst(false);

    expect(controller.settings.libraryLocalFirst, isTrue);
    expect(controller.error, isNotNull);
    expect(controller.saving, isFalse);

    controlled.failWrite = false;
    await controller.setLibraryLocalFirst(false);

    expect(controller.settings.libraryLocalFirst, isFalse);
    expect(controlled.saved.libraryLocalFirst, isFalse);
    expect(controller.error, isNull);
    expect(controller.saving, isFalse);
  });

  test('rapid edits update immediately and flush waits for every serialized save', () async {
    final controlled = _QueuedStorage();
    addTearDown(controlled.releaseAll);
    controller.dispose();
    controller = DisplaySettingsController(storage: controlled);
    await controller.initialize();

    final first = controller.setLibraryLocalFirst(false);
    final second = controller.setPlaylistsLocalFirst(false);
    final third = controller.setLibraryLocalFirst(true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.saving, isTrue);
    expect(controller.settings.toJson(), {
      'libraryLocalFirst': true,
      'playlistsLocalFirst': false,
      'likesLocalFirst': true,
    });
    expect(controlled.started, hasLength(1));

    var flushed = false;
    final flush = controller.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);

    expect(flushed, isFalse);
    controlled.releaseNext();
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(controller.saving, isTrue);
    expect(flushed, isFalse);
    expect(controlled.started, hasLength(2));
    controlled.releaseNext();
    await second;
    await Future<void>.delayed(Duration.zero);

    expect(controller.saving, isTrue);
    expect(flushed, isFalse);
    expect(controlled.started, hasLength(3));
    controlled.releaseNext();
    await Future.wait([third, flush]);

    expect(flushed, isTrue);
    expect(controller.saving, isFalse);
    expect(controlled.saved, controller.settings);
    expect(controlled.started, [
      const DisplaySettings(libraryLocalFirst: false),
      const DisplaySettings(libraryLocalFirst: false, playlistsLocalFirst: false),
      const DisplaySettings(playlistsLocalFirst: false),
    ]);
    expect(controlled.maximumConcurrentWrites, 1);
  });

  test('a failed older save cannot replace a newer edit', () async {
    final controlled = _QueuedStorage();
    addTearDown(controlled.releaseAll);
    controller.dispose();
    controller = DisplaySettingsController(storage: controlled);
    await controller.initialize();

    final first = controller.setLibraryLocalFirst(false);
    final second = controller.setLikesLocalFirst(false);
    await Future<void>.delayed(Duration.zero);

    controlled.releaseNext(fail: true);
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(controller.settings, const DisplaySettings(libraryLocalFirst: false, likesLocalFirst: false));
    expect(controller.saving, isTrue);
    controlled.releaseNext();
    await second;

    expect(controlled.saved, controller.settings);
    expect(controller.error, isNull);
    expect(controller.saving, isFalse);
  });

  test('a failed latest save rolls back to the last successfully persisted settings', () async {
    final controlled = _QueuedStorage();
    addTearDown(controlled.releaseAll);
    controller.dispose();
    controller = DisplaySettingsController(storage: controlled);
    await controller.initialize();

    final first = controller.setLibraryLocalFirst(false);
    final second = controller.setLikesLocalFirst(false);
    await Future<void>.delayed(Duration.zero);

    controlled.releaseNext();
    await first;
    await Future<void>.delayed(Duration.zero);
    controlled.releaseNext(fail: true);
    await second;

    expect(controller.settings, const DisplaySettings(libraryLocalFirst: false));
    expect(controller.settings, controlled.saved);
    expect(controller.error, isNotNull);
    expect(controller.saving, isFalse);
  });

  test('disposing during initialization prevents late notifications', () async {
    final controlled = _ControlledStorage(delayRead: true);
    final disposed = DisplaySettingsController(storage: controlled);
    var notifications = 0;
    disposed.addListener(() => notifications++);

    final initialization = disposed.initialize();
    disposed.dispose();
    final beforeReadCompletes = notifications;
    controlled.finishRead();
    await initialization;

    expect(notifications, beforeReadCompletes);
  });
}

class _ControlledStorage extends DisplaySettingsStorage {
  final bool delayRead;
  final Completer<void> _read = Completer<void>();
  DisplaySettings saved;
  int reads = 0;
  int writes = 0;
  bool failWrite = false;

  _ControlledStorage({DisplaySettings initial = const DisplaySettings(), this.delayRead = false}) : saved = initial;

  void finishRead() => _read.complete();

  @override
  Future<DisplaySettings> read() async {
    reads++;

    if (delayRead) {
      await _read.future;
    }

    return saved;
  }

  @override
  Future<void> write(DisplaySettings settings) async {
    writes++;

    if (failWrite) {
      throw const FileSystemException('Settings folder is read-only');
    }

    saved = settings;
  }
}

class _QueuedStorage extends DisplaySettingsStorage {
  final List<DisplaySettings> started = [];
  final List<Completer<void>> _writes = [];
  DisplaySettings saved = const DisplaySettings();
  int maximumConcurrentWrites = 0;
  int _activeWrites = 0;
  bool _released = false;

  void releaseNext({bool fail = false}) {
    final write = _writes.firstWhere((write) => !write.isCompleted);

    if (fail) {
      write.completeError(const FileSystemException('Settings folder is read-only'));
    } else {
      write.complete();
    }
  }

  void releaseAll() {
    _released = true;

    for (final write in _writes) {
      if (!write.isCompleted) {
        write.complete();
      }
    }
  }

  @override
  Future<DisplaySettings> read() async => saved;

  @override
  Future<void> write(DisplaySettings settings) async {
    final completion = Completer<void>();

    started.add(settings);
    _writes.add(completion);
    _activeWrites++;

    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }

    try {
      if (!_released) {
        await completion.future;
      }

      saved = settings;
    } finally {
      _activeWrites--;
    }
  }
}

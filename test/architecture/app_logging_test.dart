import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/log_storage_settings.dart';
import 'package:phonolite_app/persistence/log_files.dart';
import 'package:phonolite_app/persistence/settings_files.dart';

class BlockingLogFiles extends LogFiles {
  BlockingLogFiles(Directory directory)
    : super(directoryProvider: () async => directory);

  final writing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> append(Map<String, List<String>> entries) async {
    if (!writing.isCompleted) {
      writing.complete();
      await release.future;
    }
    await super.append(entries);
  }
}

class FailingLogFiles extends LogFiles {
  FailingLogFiles(Directory directory)
    : super(directoryProvider: () async => directory);

  bool failNextWrite = true;

  @override
  Future<void> append(Map<String, List<String>> entries) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Storage temporarily unavailable');
    }
    await super.append(entries);
  }
}

void main() {
  late Directory temp;
  final loggers = <AppLogger>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phonolite_logging_test_');
  });
  tearDown(() async {
    for (final logger in loggers) {
      await logger.flush();
    }
    loggers.clear();
    await temp.delete(recursive: true);
  });

  Future<AppLogger> open({LogFiles? files}) async {
    final logger = AppLogger();
    loggers.add(logger);
    await logger.initialize(
      files: files ?? LogFiles(directoryProvider: () async => temp),
    );
    return logger;
  }

  Future<List<String>> lines(LogCategory category) =>
      File('${temp.path}/${category.fileName}').readAsLines();

  LogEntry event(String message, [LogLevel level = LogLevel.info]) =>
      LogEntry(message: message, level: level);

  test(
    'creates all category files and routes each event independently',
    () async {
      final logger = await open();
      for (final level in LogLevel.values) {
        logger.log(event('event-${level.name}', level));
      }
      await logger.flush();

      expect(await lines(LogCategory.all), hasLength(5));
      final expected = {
        LogCategory.info: ['event-info'],
        LogCategory.activities: ['event-status'],
        LogCategory.warnings: ['event-warning'],
        LogCategory.errors: ['event-error'],
        LogCategory.issues: ['event-warning', 'event-error'],
        LogCategory.debug: ['event-debug'],
      };
      for (final category in expected.keys) {
        expect(
          (await lines(
            category,
          )).map((line) => LogEntry.fromFile(line)!.message),
          expected[category],
        );
      }
      expect(logger.storageDirectory, temp.path);
    },
  );

  test(
    'removes only oldest lines at 3000, independently for each file',
    () async {
      final logger = await open();
      for (var i = 0; i < 3000; i++) {
        logger.log(event('info-$i'));
      }
      await logger.flush();
      logger.log(event('error-0', LogLevel.error));
      logger.log(event('error-1', LogLevel.error));
      logger.log(event('info-3000'));
      await logger.flush();

      final all = await lines(LogCategory.all);
      final info = await lines(LogCategory.info);
      expect(all, hasLength(3000));
      expect(all.first, endsWith('info-3'));
      expect(all.last, endsWith('info-3000'));
      expect(info, hasLength(3000));
      expect(info.first, endsWith('info-1'));
      expect(info.last, endsWith('info-3000'));
      expect(await lines(LogCategory.errors), hasLength(2));
      expect(await lines(LogCategory.issues), hasLength(2));

      // Exercise replacement again after restart, when counts come from disk.
      final restarted = await open();
      restarted.log(event('info-3001'));
      await restarted.flush();
      expect(await lines(LogCategory.all), hasLength(3000));
      expect((await lines(LogCategory.info)).first, endsWith('info-2'));
      expect((await lines(LogCategory.info)).last, endsWith('info-3001'));
    },
  );

  test('normalizes oversized prior files before replaying history', () async {
    final oldLines = [
      for (var i = 0; i < 3100; i++) event('old-$i').formatForFile(),
    ];
    for (final category in [LogCategory.all, LogCategory.info]) {
      // No final newline simulates an interrupted or legacy file.
      await File(
        '${temp.path}/${category.fileName}',
      ).writeAsString(oldLines.join('\n'));
    }
    final logger = await open();
    final replayed = <LogEntry>[];
    logger.attach(replayed.add);
    expect(replayed, hasLength(3000));
    expect(replayed.first.message, 'old-100');
    expect(replayed.last.message, 'old-3099');
    logger.log(event('new'));
    await logger.flush();
    for (final category in [LogCategory.all, LogCategory.info]) {
      expect(await lines(category), hasLength(3000));
      expect((await lines(category)).first, endsWith('old-101'));
      expect((await lines(category)).last, endsWith('new'));
    }
  });

  test(
    'persists startup entries and replays multiline messages losslessly',
    () async {
      final logger = AppLogger();
      loggers.add(logger);
      final timestamp = DateTime.utc(2026, 10, 6, 12, 34, 56, 789);
      const message = 'first\r\nsecond\nthird\\n literal \\ path';
      logger.log(
        LogEntry(message: message, level: LogLevel.error, timestamp: timestamp),
      );
      final files = LogFiles(directoryProvider: () async => temp);
      final initialization = logger.initialize(files: files);
      expect(logger.initialize(files: files), same(initialization));
      await initialization;
      expect(await lines(LogCategory.all), hasLength(1));
      final restarted = await open();
      final replayed = <LogEntry>[];
      restarted.attach(replayed.add);
      expect(replayed.single.message, message);
      expect(replayed.single.timestamp.toUtc(), timestamp);
      expect(replayed.single.level, LogLevel.error);
    },
  );

  test(
    'clear orders active writes before deletion and retains newer events',
    () async {
      final files = BlockingLogFiles(temp);
      final logger = await open(files: files);
      logger.log(event('before clear', LogLevel.warning));
      await files.writing.future;
      final clearing = logger.clear();
      logger.log(event('after clear', LogLevel.status));
      files.release.complete();
      await clearing;

      expect(await lines(LogCategory.all), hasLength(1));
      expect((await lines(LogCategory.all)).single, endsWith('after clear'));
      expect(await lines(LogCategory.activities), hasLength(1));
      expect(await lines(LogCategory.warnings), isEmpty);
      expect(await lines(LogCategory.issues), isEmpty);
      final replayed = <LogEntry>[];
      logger.attach(replayed.add);
      expect(replayed.single.message, 'after clear');
      await logger.clear();
      for (final category in LogCategory.values) {
        expect(await lines(category), isEmpty);
      }
      final restarted = await open();
      final history = <LogEntry>[];
      restarted.attach(history.add);
      expect(history, isEmpty);
    },
  );

  test(
    'a large burst on a slow disk retains newest lines in every category',
    () async {
      final files = BlockingLogFiles(temp);
      final logger = await open(files: files);
      logger.log(event('initial'));
      await files.writing.future;
      logger.log(event('rare warning', LogLevel.warning));
      for (var i = 0; i < 4000; i++) {
        logger.log(event('burst-$i'));
      }
      files.release.complete();
      await logger.flush();
      expect(await lines(LogCategory.all), hasLength(3000));
      expect((await lines(LogCategory.all)).first, endsWith('burst-1000'));
      expect((await lines(LogCategory.all)).last, endsWith('burst-3999'));
      expect(await lines(LogCategory.info), hasLength(3000));
      expect(
        (await lines(LogCategory.warnings)).single,
        endsWith('rare warning'),
      );
      expect(
        (await lines(LogCategory.issues)).single,
        endsWith('rare warning'),
      );
    },
  );

  test('failed writes are visible and subsequent writes can recover', () async {
    final logger = await open(files: FailingLogFiles(temp));
    logger.log(event('first'));
    await logger.flush();
    expect(logger.persistenceError, contains('temporarily unavailable'));
    final replayed = <LogEntry>[];
    logger.attach(replayed.add);
    expect(replayed.last.level, LogLevel.error);
    expect(replayed.last.message, contains('Unable to save local logs'));
    logger.log(event('recovered'));
    await logger.flush();
    expect(logger.persistenceError, isNull);
    expect((await lines(LogCategory.all)).single, endsWith('recovered'));
    await logger.clear();
    for (final category in LogCategory.values) {
      expect(await lines(category), isEmpty);
    }
  });

  test(
    'initialization failures keep ordinary in-memory logging available',
    () async {
      final logger = await open(
        files: LogFiles(
          directoryProvider: () async =>
              throw const FileSystemException('Read only'),
        ),
      );
      logger.log(event('still operating'));
      await logger.flush();
      final history = <LogEntry>[];
      logger.attach(history.add);
      expect(logger.persistenceError, contains('Read only'));
      expect(history, hasLength(2));
      expect(history.last.message, 'still operating');
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test(
    'construction performs no I/O and retains exactly newest 3000 entries',
    () async {
      final logger = AppLogger();
      for (var i = 0; i < 4000; i++) {
        logger.log(event('entry-$i'));
      }
      final history = <LogEntry>[];
      logger.attach(history.add);
      expect(history, hasLength(3000));
      expect(history.first.message, 'entry-1000');
      expect(history.last.message, 'entry-3999');
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test('Windows uses LocalAppData with support-directory fallback', () async {
    var supportRequested = false;
    Future<Directory> support() async {
      supportRequested = true;
      return Directory('${temp.path}/app-support');
    }

    final local = await LogFiles.defaultDirectory(
      operatingSystem: 'windows',
      environment: {'LOCALAPPDATA': '${temp.path}/local-app-data'},
      supportDirectoryProvider: support,
    );
    expect(local.path, '${temp.path}/local-app-data/Phonolite/logs');
    expect(supportRequested, isFalse);
    final fallback = await LogFiles.defaultDirectory(
      operatingSystem: 'windows',
      environment: {'LOCALAPPDATA': ' '},
      supportDirectoryProvider: support,
    );
    expect(fallback.path, '${temp.path}/app-support/logs');
    expect(supportRequested, isTrue);
  });

  test(
    'folder changes and reset persist without duplicating bounded history',
    () async {
      final defaultFolder = Directory('${temp.path}/default');
      final customFolder = Directory('${temp.path}/custom logs');
      final preferences = LogStorageSettingsStorage(
        files: SettingsFiles(
          directoryProvider: () async => Directory('${temp.path}/settings'),
        ),
        usesManagedStoragePaths: () => false,
      );
      LogFiles files() => LogFiles(
        directoryProvider: () async => defaultFolder,
        settingsStorage: preferences,
        maxLines: 3,
      );
      final logger = await open(files: files());
      final locations = <LogStorageLocation>[];
      final subscription = logger.storageLocationStream.listen(locations.add);
      addTearDown(subscription.cancel);
      LogEntry timedEvent(String message, int microseconds) => LogEntry(
        message: message,
        level: LogLevel.info,
        timestamp: DateTime.utc(
          2026,
          10,
          12,
        ).add(Duration(microseconds: microseconds)),
      );
      logger.log(timedEvent('first', 0));
      logger.log(timedEvent('second', 1));
      await logger.flush();
      final unrelated = File('${defaultFolder.path}/notes.txt');
      await unrelated.writeAsString('keep this');
      await customFolder.create(recursive: true);
      await File(
        '${customFolder.path}/all.log',
      ).writeAsString('${timedEvent('second', 1).formatForFile()}\n');

      await logger.updateStorageDirectory(customFolder.path);
      logger.log(timedEvent('third', 1000));
      logger.log(timedEvent('fourth', 1000));
      await logger.flush();
      expect(logger.storageDirectory, customFolder.path);
      expect(logger.storageLocation!.isDefault, isFalse);
      expect(await File('${defaultFolder.path}/all.log').exists(), isFalse);
      expect(await unrelated.readAsString(), 'keep this');
      expect(await preferences.read(), customFolder.path);
      final restarted = await open(files: files());
      expect(restarted.storageDirectory, customFolder.path);

      await logger.updateStorageDirectory(null);
      await logger.flush();
      expect(logger.storageDirectory, defaultFolder.path);
      expect(logger.storageLocation!.isDefault, isTrue);
      expect(await preferences.read(), isNull);
      final restored = await open(files: files());
      expect(restored.storageDirectory, defaultFolder.path);
      final history = <LogEntry>[];
      restored.attach(history.add);
      expect(history.map((entry) => entry.message), [
        'second',
        'third',
        'fourth',
      ]);
      expect(locations.map((location) => location.isDefault), [false, true]);
      expect(await File('${customFolder.path}/all.log').exists(), isFalse);
    },
  );

  test(
    'folder changes wait for active writes and keep events logged during the change',
    () async {
      final files = BlockingLogFiles(temp);
      final logger = await open(files: files);
      logger.log(event('before change'));
      await files.writing.future;
      final target = Directory('${temp.path}/next');
      final changing = logger.updateStorageDirectory(target.path);
      logger.log(event('during change', LogLevel.warning));
      files.release.complete();
      await changing;
      await logger.flush();
      final moved = await File('${target.path}/all.log').readAsLines();
      expect(moved.map((line) => LogEntry.fromFile(line)!.message), [
        'before change',
        'during change',
      ]);
      expect(
        (await File('${target.path}/warnings.log').readAsLines()).single,
        endsWith('during change'),
      );
      await logger.clear();
      expect(await File('${target.path}/all.log').readAsLines(), isEmpty);
      logger.log(event('after clear'));
      await logger.flush();
      expect(
        (await File('${target.path}/all.log').readAsLines()).single,
        endsWith('after clear'),
      );
    },
  );

  test('failed preference saves leave logging in the current folder', () async {
    final blocker = File('${temp.path}/settings-blocker');
    await blocker.writeAsString('not a folder');
    final original = Directory('${temp.path}/original');
    final logger = await open(
      files: LogFiles(
        directoryProvider: () async => original,
        settingsStorage: LogStorageSettingsStorage(
          files: SettingsFiles(
            directoryProvider: () async => Directory(blocker.path),
          ),
          usesManagedStoragePaths: () => false,
        ),
      ),
    );
    logger.log(event('kept'));
    await logger.flush();
    await expectLater(
      logger.updateStorageDirectory('${temp.path}/new-folder'),
      throwsA(isA<FileSystemException>()),
    );
    expect(logger.storageDirectory, original.path);
    expect(logger.storageLocation!.isDefault, isTrue);
    logger.log(event('still writing'));
    await logger.flush();
    expect(
      (await File('${original.path}/all.log').readAsLines()).last,
      endsWith('still writing'),
    );
  });

  test(
    'changing folder recovers persisted history after a failed append',
    () async {
      final original = Directory('${temp.path}/original');
      await original.create();
      await File(
        '${original.path}/all.log',
      ).writeAsString('${event('persisted').formatForFile()}\n');
      final logger = await open(files: FailingLogFiles(original));
      logger.log(event('write that fails'));
      await logger.flush();
      expect(logger.persistenceError, isNotNull);
      final target = Directory('${temp.path}/recovered');
      await logger.updateStorageDirectory(target.path);
      logger.log(event('after recovery'));
      await logger.flush();
      final history = await File('${target.path}/all.log').readAsLines();
      expect(history.map((line) => LogEntry.fromFile(line)!.message), [
        'persisted',
        'after recovery',
      ]);
    },
  );

  for (final platform in ['android', 'ios', 'macos', 'linux']) {
    test('$platform keeps logs in its application support directory', () async {
      final directory = await LogFiles.defaultDirectory(
        operatingSystem: platform,
        environment: {},
        supportDirectoryProvider: () async =>
            Directory('${temp.path}/$platform'),
      );
      expect(directory.path, '${temp.path}/$platform/logs');
    });
  }
}

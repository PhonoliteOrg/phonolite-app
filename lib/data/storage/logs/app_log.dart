import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/storage/logs/log_files.dart';

class AppLogger {
  static const int _maxBuffer = 3000;

  static final AppLogger instance = AppLogger();
  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();
  final List<LogListener> _listeners = <LogListener>[];
  final Map<String, ListQueue<String>> _pending = {};
  final Queue<_LogDirectoryChange> _directoryChanges = Queue();
  final StreamController<LogStorageLocation> _storageLocationController =
      StreamController<LogStorageLocation>.broadcast();
  LogFiles? _files;
  Future<void>? _initialization;
  Future<void>? _writer;
  bool _clearRequested = false;
  String? _persistenceError;

  AppLogger();

  String? get storageDirectory => _files?.directoryPath;

  /// Current committed location, or null before persistent files are available.
  LogStorageLocation? get storageLocation => _files?.storageLocation;

  /// Asynchronous broadcast updates after initialization and committed moves.
  ///
  /// There is no initial emission or replay; [storageLocation] is a separate
  /// current-state read. Persistence failures are reported through logs and
  /// [persistenceError], never as stream errors. The application logger owns
  /// this stream for its lifetime and does not expose a close operation.
  Stream<LogStorageLocation> get storageLocationStream => _storageLocationController.stream;

  String? get persistenceError => _persistenceError;

  /// Opt in at app startup; construction and ordinary unit tests do no I/O.
  Future<void> initialize({LogFiles? files}) => _initialization ??= _initialize(files ?? LogFiles());

  void attach(LogListener listener, {bool includeHistory = true}) {
    _listeners.add(listener);

    if (includeHistory) {
      for (final entry in _buffer) {
        listener(entry);
      }
    }
  }

  void detach(LogListener listener) {
    _listeners.remove(listener);
  }

  void log(LogEntry entry) {
    _publish(entry);

    if (_files != null) {
      _queue(entry);
    }
  }

  Future<void> flush() async {
    while (_writer != null) {
      await _writer;
    }
  }

  Future<void> clear() {
    _buffer.clear();
    _pending.clear();

    if (_files != null) {
      _clearRequested = true;
      _scheduleWriter();
    }

    return flush();
  }

  Future<void> updateStorageDirectory(String? path) async {
    await initialize();

    if (_files == null) {
      throw StateError('Local log files are unavailable.');
    }

    final change = _LogDirectoryChange(path);

    _directoryChanges.add(change);
    _scheduleWriter();

    await change.completion.future;
  }

  static void info(String message) {
    instance.log(LogEntry(message: message, level: LogLevel.info));
  }

  static void status(String message) {
    instance.log(LogEntry(message: message, level: LogLevel.status));
  }

  static void warning(String message) {
    instance.log(LogEntry(message: message, level: LogLevel.warning));
  }

  static void error(String message) {
    instance.log(LogEntry(message: message, level: LogLevel.error));
  }

  static void debug(String message) {
    instance.log(LogEntry(message: message, level: LogLevel.debug));
  }

  Future<void> _initialize(LogFiles files) async {
    if (kIsWeb) {
      return;
    }

    try {
      await files.initialize(LogCategory.values.map((value) => value.fileName));
      final startupEntries = List<LogEntry>.from(_buffer);

      _buffer.clear();

      for (final line in files.read(LogCategory.all.fileName)) {
        final entry = LogEntry.fromFile(line);

        if (entry != null) {
          _publish(entry);
        }
      }

      // Startup messages already reached listeners; retain and persist them
      // after the history without delivering them a second time.
      for (final entry in startupEntries) {
        _retain(entry);
      }

      _files = files;
      _storageLocationController.add(files.storageLocation!);

      for (final entry in startupEntries) {
        _queue(entry);
      }

      await flush();
    } catch (error) {
      _reportPersistenceError(error);
    }
  }

  void _retain(LogEntry entry) {
    _buffer.add(entry);

    if (_buffer.length > _maxBuffer) {
      _buffer.removeFirst();
    }
  }

  void _publish(LogEntry entry) {
    _retain(entry);

    for (final listener in List<LogListener>.from(_listeners)) {
      listener(entry);
    }
  }

  void _queue(LogEntry entry) {
    final line = entry.formatForFile();

    for (final category in entry.categories) {
      final lines = _pending.putIfAbsent(category.fileName, ListQueue.new);

      lines.add(line);

      if (lines.length > _files!.maxLines) {
        lines.removeFirst();
      }
    }

    _scheduleWriter();
  }

  void _scheduleWriter() {
    // One async writer batches bursts without holding up playback or queuing
    // an unbounded number of file operations behind a slow disk.
    _writer ??= Future<void>(_drain);
  }

  Future<void> _drain() async {
    try {
      while (_clearRequested || _pending.isNotEmpty || _directoryChanges.isNotEmpty) {
        try {
          if (_clearRequested) {
            _clearRequested = false;
            await _files!.clear();
          } else if (_directoryChanges.isNotEmpty) {
            final change = _directoryChanges.removeFirst();

            try {
              final warnings = await _files!.changeDirectory(change.path);

              for (final message in warnings) {
                log(LogEntry(message: message, level: LogLevel.warning));
              }

              _storageLocationController.add(_files!.storageLocation!);
              change.completion.complete();
            } catch (error, stack) {
              change.completion.completeError(error, stack);
            }
          } else {
            final batch = {for (final item in _pending.entries) item.key: item.value.toList(growable: false)};

            _pending.clear();
            await _files!.append(batch);
          }

          _persistenceError = null;
        } catch (error) {
          _reportPersistenceError(error);
        }
      }
    } finally {
      _writer = null;
    }
  }

  void _reportPersistenceError(Object error) {
    final alreadyReported = _persistenceError != null;

    _persistenceError = error.toString();

    if (!alreadyReported) {
      // Keep failures visible in the app without recursively trying to write
      // a log about a failed log write.
      _publish(LogEntry(message: 'Unable to save local logs: $error', level: LogLevel.error));
    }
  }
}

class _LogDirectoryChange {
  final String? path;
  final Completer<void> completion = Completer<void>();

  _LogDirectoryChange(this.path);
}

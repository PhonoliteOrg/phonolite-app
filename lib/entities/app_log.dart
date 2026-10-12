import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../persistence/log_files.dart';

typedef LogListener = void Function(LogEntry entry);

enum LogLevel { info, status, warning, error, debug }

enum LogCategory {
  all('All'),
  info('Info'),
  activities('Activities'),
  warnings('Warnings'),
  errors('Errors'),
  issues('Issues'),
  debug('Debug');

  const LogCategory(this.label);
  final String label;
  String get fileName => '$name.log';
}

class LogEntry {
  LogEntry({required this.message, required this.level, DateTime? timestamp})
    : timestamp = (timestamp ?? DateTime.now()).toLocal();

  final String message;
  final LogLevel level;
  final DateTime timestamp;

  String get levelLabel {
    switch (level) {
      case LogLevel.status:
        return 'STATUS';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
    }
  }

  String get timestampLabel {
    final year = timestamp.year.toString().padLeft(4, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  String format() => '[$timestampLabel][$levelLabel] $message';

  Iterable<LogCategory> get categories sync* {
    yield LogCategory.all;
    yield switch (level) {
      LogLevel.info => LogCategory.info,
      LogLevel.status => LogCategory.activities,
      LogLevel.warning => LogCategory.warnings,
      LogLevel.error => LogCategory.errors,
      LogLevel.debug => LogCategory.debug,
    };
    if (level == LogLevel.warning || level == LogLevel.error) {
      yield LogCategory.issues;
    }
  }

  // Escape line breaks so one event, including a stack trace, is one physical
  // line. Escape backslashes too so history can recover the original message.
  String formatForFile() {
    final escaped = message
        .replaceAll('\\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');
    return '[${timestamp.toUtc().toIso8601String()}][$levelLabel] $escaped';
  }

  static LogEntry? fromFile(String line) {
    final match = RegExp(r'^\[([^\]]+)\]\[([A-Z]+)\] (.*)$').firstMatch(line);
    if (match == null) return null;
    final timestamp = DateTime.tryParse(match[1]!);
    final level = switch (match[2]) {
      'INFO' => LogLevel.info,
      'STATUS' => LogLevel.status,
      'WARN' => LogLevel.warning,
      'ERROR' => LogLevel.error,
      'DEBUG' => LogLevel.debug,
      _ => null,
    };
    if (timestamp == null || level == null) return null;
    final message = match[3]!.replaceAllMapped(RegExp(r'\\([\\rn])'), (escape) {
      return switch (escape[1]) {
        'r' => '\r',
        'n' => '\n',
        _ => '\\',
      };
    });
    return LogEntry(message: message, level: level, timestamp: timestamp);
  }
}

class AppLogger {
  AppLogger();

  static final AppLogger instance = AppLogger();
  static const int _maxBuffer = 3000;

  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();
  final List<LogListener> _listeners = <LogListener>[];
  final Map<String, ListQueue<String>> _pending = {};
  LogFiles? _files;
  Future<void>? _initialization;
  Future<void>? _writer;
  bool _clearRequested = false;
  String? _persistenceError;

  String? get storageDirectory => _files?.directoryPath;
  String? get persistenceError => _persistenceError;

  /// Opt in at app startup; construction and ordinary unit tests do no I/O.
  Future<void> initialize({LogFiles? files}) =>
      _initialization ??= _initialize(files ?? LogFiles());

  Future<void> _initialize(LogFiles files) async {
    if (kIsWeb) return;
    try {
      await files.initialize(LogCategory.values.map((value) => value.fileName));
      final startupEntries = List<LogEntry>.from(_buffer);
      _buffer.clear();
      for (final line in files.read(LogCategory.all.fileName)) {
        final entry = LogEntry.fromFile(line);
        if (entry != null) _publish(entry);
      }
      // Startup messages already reached listeners; retain and persist them
      // after the history without delivering them a second time.
      for (final entry in startupEntries) {
        _retain(entry);
      }
      _files = files;
      for (final entry in startupEntries) {
        _queue(entry);
      }
      await flush();
    } catch (error) {
      _reportPersistenceError(error);
    }
  }

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
    if (_files != null) _queue(entry);
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
      if (lines.length > _files!.maxLines) lines.removeFirst();
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
      while (_clearRequested || _pending.isNotEmpty) {
        try {
          if (_clearRequested) {
            _clearRequested = false;
            await _files!.clear();
          } else {
            final batch = {
              for (final item in _pending.entries)
                item.key: item.value.toList(growable: false),
            };
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
      _publish(
        LogEntry(
          message: 'Unable to save local logs: $error',
          level: LogLevel.error,
        ),
      );
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
}

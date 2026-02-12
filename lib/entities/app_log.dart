typedef LogListener = void Function(LogEntry entry);

enum LogLevel { info, status, warning, error, debug }

class LogEntry {
  LogEntry({
    required this.message,
    required this.level,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toLocal();

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
      default:
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
}

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();
  static const int _maxBuffer = 3000;
  static const int _trimChunk = 500;

  final List<LogEntry> _buffer = <LogEntry>[];
  final List<LogListener> _listeners = <LogListener>[];

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
    _buffer.add(entry);
    if (_buffer.length > _maxBuffer) {
      final count = _trimChunk.clamp(0, _buffer.length);
      if (count > 0) {
        _buffer.removeRange(0, count);
      }
    }
    for (final listener in List<LogListener>.from(_listeners)) {
      listener(entry);
    }
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

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

  final String label;

  const LogCategory(this.label);

  String get fileName => '$name.log';
}

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({required this.message, required this.level, DateTime? timestamp})
    : timestamp = (timestamp ?? DateTime.now()).toLocal();

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

  String format() => '[$timestampLabel][$levelLabel] $message';

  // Escape line breaks so one event, including a stack trace, is one physical
  // line. Escape backslashes too so history can recover the original message.
  String formatForFile() {
    final escaped = message.replaceAll('\\', r'\\').replaceAll('\r', r'\r').replaceAll('\n', r'\n');

    return '[${timestamp.toUtc().toIso8601String()}][$levelLabel] $escaped';
  }

  static LogEntry? fromFile(String line) {
    final match = RegExp(r'^\[([^\]]+)\]\[([A-Z]+)\] (.*)$').firstMatch(line);
    if (match == null) {
      return null;
    }

    final timestamp = DateTime.tryParse(match[1]!);
    final level = switch (match[2]) {
      'INFO' => LogLevel.info,
      'STATUS' => LogLevel.status,
      'WARN' => LogLevel.warning,
      'ERROR' => LogLevel.error,
      'DEBUG' => LogLevel.debug,
      _ => null,
    };

    if (timestamp == null || level == null) {
      return null;
    }

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

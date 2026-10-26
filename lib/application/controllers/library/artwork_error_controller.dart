import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class ArtworkErrorController {
  static const _repeatInterval = Duration(minutes: 5);
  static const _maxRecentFailures = 256;

  final AppLogger _logger;
  final DateTime Function() _now;
  final _recent = <String, DateTime>{};

  ArtworkErrorController({AppLogger? logger, DateTime Function()? now})
    : _logger = logger ?? AppLogger.instance,
      _now = now ?? DateTime.now;

  static String safeSource(String source) {
    final uri = Uri.tryParse(source);

    return uri != null && uri.hasAuthority
        ? uri
              .replace(
                userInfo: '',
                queryParameters: {if (uri.queryParameters['kind'] case final kind?) 'kind': kind},
                fragment: '',
              )
              .toString()
        : source;
  }

  /// Decoder and transport messages may repeat a URL, including its secrets.
  static String safeError(Object error) {
    final message = error
        .toString()
        .replaceAllMapped(RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false), (match) => safeSource(match[0]!))
        .replaceAll(RegExp(r'\bBearer\s+[a-z0-9._~+/=-]+', caseSensitive: false), 'Bearer [redacted]')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');

    return message.length > 512 ? '${message.substring(0, 512)}…' : message;
  }

  void report(String source, Object error, {int? status}) {
    final key = '$source:${status ?? error.runtimeType}';
    final now = _now();
    final previous = _recent[key];

    if (previous != null && now.difference(previous) < _repeatInterval) {
      return;
    }

    _recent.remove(key);
    _recent[key] = now;

    if (_recent.length > _maxRecentFailures) {
      _recent.remove(_recent.keys.first);
    }

    // Keep credentials and arbitrary query parameters out of diagnostics.
    final displaySource = safeSource(source);
    final missing = status == 404 || status == 410;

    _logger.log(
      LogEntry(
        message:
            '${missing ? 'Artwork unavailable' : 'Unable to load artwork'}'
            '${status == null ? ' (${error.runtimeType})' : ' (HTTP $status)'}: '
            '$displaySource; using placeholder. Error: ${safeError(error)}',
        level: missing ? LogLevel.info : LogLevel.warning,
      ),
    );
  }
}

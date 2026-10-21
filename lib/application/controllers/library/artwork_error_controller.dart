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
    final uri = Uri.tryParse(source);
    final displaySource = uri != null && uri.hasAuthority
        ? uri
              .replace(
                userInfo: '',
                queryParameters: {if (uri.queryParameters['kind'] case final kind?) 'kind': kind},
                fragment: '',
              )
              .toString()
        : source;
    final missing = status == 404 || status == 410;

    _logger.log(
      LogEntry(
        message:
            '${missing ? 'Artwork unavailable' : 'Unable to load artwork'}'
            '${status == null ? ' (${error.runtimeType})' : ' (HTTP $status)'}: '
            '$displaySource; using placeholder.',
        level: missing ? LogLevel.info : LogLevel.warning,
      ),
    );
  }
}

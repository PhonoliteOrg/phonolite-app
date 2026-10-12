import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../entities/app_log.dart';

/// Shared by image fallbacks and prefetching, including failures that arrive
/// after a widget has gone away. A rebuild must not flood the log with 404s.
class ArtworkErrors {
  ArtworkErrors({AppLogger? logger, DateTime Function()? now})
    : _logger = logger ?? AppLogger.instance,
      _now = now ?? DateTime.now;

  static final instance = ArtworkErrors();
  static const _repeatInterval = Duration(minutes: 5);
  static const _maxRecentFailures = 256;

  final AppLogger _logger;
  final DateTime Function() _now;
  final _recent = <String, DateTime>{};

  void report(String source, Object error) {
    final status = error is NetworkImageLoadException ? error.statusCode : null;
    final key = '$source:${status ?? error.runtimeType}';
    final now = _now();
    final previous = _recent[key];
    if (previous != null && now.difference(previous) < _repeatInterval) return;
    _recent.remove(key);
    _recent[key] = now;
    if (_recent.length > _maxRecentFailures) _recent.remove(_recent.keys.first);

    // Keep credentials and arbitrary query parameters out of diagnostics.
    final uri = Uri.tryParse(source);
    final displaySource = uri != null && uri.hasAuthority
        ? uri
              .replace(
                userInfo: '',
                queryParameters: {
                  if (uri.queryParameters['kind'] case final kind?)
                    'kind': kind,
                },
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

  /// Handle only network-image resource failures; other framework exceptions
  /// must still reach Flutter's normal error handler.
  bool handleFlutterError(FlutterErrorDetails details) {
    final error = details.exception;
    if (details.library != 'image resource service' ||
        error is! NetworkImageLoadException) {
      return false;
    }
    report(error.uri.toString(), error);
    return true;
  }
}

void installArtworkErrorHandler() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (ArtworkErrors.instance.handleFlutterError(details)) return;
    (previous ?? FlutterError.presentError)(details);
  };
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:phonolite_app/application/controllers/library/artwork_error_controller.dart';
import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

/// Debug-only metadata checkpoints for tiles that actually enter the grid.
/// Rebuilds are deduplicated and history is bounded for large libraries.
class ArtistArtworkDiagnostics {
  final AppLogger _logger;
  final bool enabled;
  final _tiles = <(int, String), (String?, String?)>{};

  ArtistArtworkDiagnostics({AppLogger? logger, this.enabled = kDebugMode}) : _logger = logger ?? AppLogger.instance;

  void tile(Artist artist, {required int sessionRevision}) {
    if (!enabled) {
      return;
    }

    final key = (sessionRevision, artist.id);
    final refs = (artist.logoRef, artist.bannerRef);
    if (_tiles[key] == refs) {
      return;
    }

    _tiles.remove(key);
    _tiles[key] = refs;
    if (_tiles.length > 256) {
      _tiles.remove(_tiles.keys.first);
    }

    final eligible = artist.logoRef?.isNotEmpty == true;
    _debug('tile ${_describe(artist)}; image=${eligible ? 'eligible' : 'skipped: no logo reference'}');
  }

  void opening(Artist artist) => _debug('detail-open ${_describe(artist)}');

  void refreshed(Artist before, Artist after, {required int elapsedMs}) => _debug(
    'detail-response ${_describe(after)}; elapsed=${elapsedMs}ms; '
    'logoChanged=${before.logoRef != after.logoRef}; bannerChanged=${before.bannerRef != after.bannerRef}',
  );

  void failed(Artist artist, Object error, {required int elapsedMs}) => _debug(
    'detail-failed ${_describe(artist)}; elapsed=${elapsedMs}ms; error=${ArtworkErrorController.safeError(error)}',
  );

  String _describe(Artist artist) =>
      'id=${jsonEncode(artist.id)} name=${jsonEncode(artist.name)} '
      'logo=${artist.logoRef?.isNotEmpty == true ? 'present' : 'missing'} '
      'banner=${artist.bannerRef?.isNotEmpty == true ? 'present' : 'missing'}';

  void _debug(String message) {
    if (enabled) {
      _logger.log(LogEntry(message: 'Artist artwork $message', level: LogLevel.debug));
    }
  }
}

import 'dart:typed_data';

import 'package:phonolite_app/application/workflows/request_generation.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/artwork/now_playing_artwork_loader.dart';

/// Owns the current artwork request and suppresses stale completions.
class NowPlayingArtwork {
  final NowPlayingArtworkLoader _loader;
  ({String key, String token})? _source;
  Uint8List? _bytes;
  final _requests = RequestGeneration();
  bool _loading = false;

  NowPlayingArtwork({required this._loader});

  String? get key => _source?.key;

  Uint8List? get bytes => _bytes?.asUnmodifiableView();

  static String? sourceKey({String? url, String? localPath}) {
    final path = localPath?.trim();

    if (path != null && path.isNotEmpty) {
      return 'file:$path';
    }

    final remote = url?.trim();

    return remote != null && remote.isNotEmpty ? 'url:$remote' : null;
  }

  void clear() {
    _requests.advance();
    _source = null;
    _bytes = null;
    _loading = false;
  }

  /// Returns true only when this request installs the current artwork.
  /// Selecting no source clears the cache immediately. Failed loads can retry.
  Future<bool> load({String? url, String? localPath, required String token}) async {
    final path = localPath?.trim();
    final remote = url?.trim();
    final local = path != null && path.isNotEmpty;
    final key = sourceKey(url: remote, localPath: path);

    if (key == null) {
      clear();

      return false;
    }

    final source = (key: key, token: token);

    if (_source == source && (_loading || _bytes != null)) {
      return false;
    }

    _source = source;
    _bytes = null;
    _loading = true;
    final generation = _requests.advance();

    try {
      final loaded = local ? await _loader.loadFile(path) : await _loader.loadRemote(remote!, token: token);

      if (!_requests.isCurrent(generation) || loaded == null) {
        return false;
      }

      _bytes = loaded;

      return true;
    } on Object catch (error) {
      // Best-effort: the player shows its placeholder and a later load retries.
      // Only the type is logged because a remote failure may carry the request.
      AppLogger.warning('Now playing artwork could not be loaded (${error.runtimeType}).');

      return false;
    } finally {
      if (_requests.isCurrent(generation)) {
        _loading = false;
      }
    }
  }
}

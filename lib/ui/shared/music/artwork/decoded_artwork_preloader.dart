import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:phonolite_app/data/models/artwork/artwork_preloader.dart';
import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';

/// Retains a small upcoming window in Flutter's live image cache. Matching
/// artwork widgets can receive their first decoded frame synchronously.
class DecodedArtworkPreloader implements ArtworkPreloader {
  final ArtworkLoader loader;
  final int maximumEntries;
  final int maximumBytes;
  final Map<ImageProvider, _PreloadedArtwork> _entries = {};
  final Set<ImageProvider> _skipped = {};
  final Set<ImageProvider> _capacitySkipped = {};
  List<ImageProvider> _order = [];
  _PreloadedArtwork? _loading;
  String? _scope;
  int _generation = 0;
  bool _draining = false;
  bool _disposed = false;

  DecodedArtworkPreloader({required this.loader, this.maximumEntries = 3, this.maximumBytes = 32 * 1024 * 1024})
    : assert(maximumEntries > 0),
      assert(maximumBytes > 0);

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    clear();
  }

  @override
  void update(Iterable<ArtworkRequest> requests) {
    if (_disposed) {
      return;
    }

    if (_scope != loader.cacheScope) {
      clear();
    }

    final desired = <ImageProvider, ArtworkRequest>{};

    for (final request in requests) {
      if (request.source.trim().isEmpty) {
        continue;
      }

      final provider = _provider(request);

      desired.putIfAbsent(provider, () => request);

      if (desired.length >= maximumEntries) {
        break;
      }
    }

    final order = desired.keys.toList(growable: false);

    if (!listEquals(_order, order)) {
      _capacitySkipped.clear();
    }

    _order = order;
    _skipped.removeWhere((key) => !desired.containsKey(key));

    for (final entry in _entries.values.toList(growable: false)) {
      if (!desired.containsKey(entry.provider)) {
        _release(entry);
      }
    }

    for (final candidate in desired.entries) {
      if (!_skipped.contains(candidate.key) && !_capacitySkipped.contains(candidate.key)) {
        _entries.putIfAbsent(
          candidate.key,
          () => _PreloadedArtwork(candidate.key, candidate.value.source, _generation),
        );
      }
    }

    _drain();
  }

  @override
  void clear() {
    _generation++;
    _scope = loader.cacheScope;

    for (final entry in _entries.values.toList(growable: false)) {
      _release(entry);
    }

    _order = [];
    _skipped.clear();
    _capacitySkipped.clear();
  }

  ImageProvider _provider(ArtworkRequest request) {
    final provider = AuthenticatedNetworkImage(
      request.source,
      loader: loader,
      headers: request.headers,
      decodeSize: request.decodeSize,
    );
    final size = request.decodeSize;

    return size == null ? provider : ResizeImage(provider, width: size, height: size, policy: ResizeImagePolicy.fit);
  }

  void _drain() {
    if (_disposed || _draining || _loading != null) {
      return;
    }

    if (_scope != loader.cacheScope) {
      clear();

      return;
    }

    _draining = true;

    try {
      while (!_disposed && _loading == null) {
        _PreloadedArtwork? next;

        for (final key in _order) {
          final entry = _entries[key];

          if (entry != null && entry.stream == null) {
            next = entry;

            break;
          }
        }

        if (next == null) {
          break;
        }

        final entry = next;

        _loading = entry;

        try {
          entry.stream = entry.provider.resolve(ImageConfiguration.empty);
          entry.listener = ImageStreamListener(
            (info, _) => _loaded(entry, info),
            onError: (Object error, StackTrace? stack) => _failed(entry, error),
          );
          // The callback can run synchronously for an already decoded cover.
          entry.stream!.addListener(entry.listener!);
        } catch (error) {
          _failed(entry, error);
        }
      }
    } finally {
      _draining = false;
    }
  }

  bool _isCurrent(_PreloadedArtwork entry) =>
      !_disposed && entry.generation == _generation && identical(_entries[entry.provider], entry);

  void _loaded(_PreloadedArtwork entry, ImageInfo info) {
    try {
      if (_scope != loader.cacheScope) {
        clear();

        return;
      }

      if (!_isCurrent(entry)) {
        return;
      }

      entry.bytes = info.image.width * info.image.height * 4;

      if (identical(_loading, entry)) {
        _loading = null;
      }

      var retained = _entries.values.fold<int>(0, (total, value) => total + (value.bytes ?? 0));

      for (final key in _order.reversed) {
        if (retained <= maximumBytes) {
          break;
        }

        final candidate = _entries[key];

        if (candidate?.bytes == null) {
          continue;
        }

        retained -= candidate!.bytes!;
        _capacitySkipped.add(key);
        _release(candidate);
      }
    } finally {
      // ImageStream listeners own the ImageInfo clone delivered to them.
      info.dispose();
    }

    _drain();
  }

  void _failed(_PreloadedArtwork entry, Object error) {
    if (!_isCurrent(entry)) {
      return;
    }

    _skipped.add(entry.provider);
    _release(entry);
    ArtworkErrors.instance.report(entry.source, error);
    _drain();
  }

  void _release(_PreloadedArtwork entry) {
    if (identical(_entries[entry.provider], entry)) {
      _entries.remove(entry.provider);
    }

    if (identical(_loading, entry)) {
      _loading = null;
    }

    final listener = entry.listener;

    if (listener != null) {
      if (entry.bytes == null) {
        // Removing our last error listener cannot cancel an in-flight load.
        // Its optional completion must remain handled after the window moves.
        entry.stream?.completer?.addEphemeralErrorListener((Object error, StackTrace? stack) {});
      }

      entry.stream?.removeListener(listener);
    }

    entry.listener = null;
  }
}

class _PreloadedArtwork {
  final ImageProvider provider;
  final String source;
  final int generation;
  ImageStream? stream;
  ImageStreamListener? listener;
  int? bytes;

  _PreloadedArtwork(this.provider, this.source, this.generation);
}

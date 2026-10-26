import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

/// Flutter stream integration for a borrowed artwork capability. Networking,
/// files, authentication and disk caching remain with the injected owner.
class AuthenticatedNetworkImage extends ImageProvider<AuthenticatedNetworkImage> {
  static final _activeLoads = Expando<Map<AuthenticatedNetworkImage, Object>>();
  static final _invalidations = Expando<Map<AuthenticatedNetworkImage, Future<void>>>();

  final String url;
  final ArtworkLoader loader;
  final Map<String, String> headers;
  final int? decodeSize;
  final String _scope;

  AuthenticatedNetworkImage(this.url, {required this.loader, Map<String, String>? headers, this.decodeSize})
    : headers = Map.unmodifiable(headers ?? const {}),
      _scope = loader.cacheScope;

  @override
  Future<AuthenticatedNetworkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(AuthenticatedNetworkImage key, ImageDecoderCallback decode) {
    final request = ArtworkRequest(source: url, headers: headers, decodeSize: decodeSize);
    final active = _activeLoads[loader] ??= <AuthenticatedNetworkImage, Object>{};
    final invalidations = _invalidations[loader] ??= <AuthenticatedNetworkImage, Future<void>>{};
    final ticket = Object();
    active[key] = ticket;
    final previousInvalidation = invalidations[key];
    var suppliedBytes = false;
    var failed = false;

    final completer = _ArtworkImageStreamCompleter(
      codec: loader.decode(_scope, () async {
        // A retry must not revalidate bytes whose failed frame is still being
        // removed from the persistent cache.
        await previousInvalidation;
        final bytes = await loader.load(request);
        suppliedBytes = true;
        return _decode(bytes, decode);
      }),
      onError: () {
        if (failed) {
          return;
        }
        failed = true;
        // ImageCache installs its pending entry after loadImage returns.
        scheduleMicrotask(() {
          if (!identical(active[key], ticket)) {
            return;
          }
          if (suppliedBytes && loader.cacheScope == _scope) {
            final invalidation = loader.invalidate(request).catchError((Object _) {});
            invalidations[key] = invalidation;
            unawaited(
              invalidation.whenComplete(() {
                if (identical(invalidations[key], invalidation)) {
                  invalidations.remove(key);
                }
              }),
            );
          }
          PaintingBinding.instance.imageCache.evict(key);
        });
      },
      onDispose: () {
        if (identical(active[key], ticket)) {
          active.remove(key);
        }
      },
    );
    return completer;
  }

  Future<ui.Codec> _decode(Uint8List bytes, ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);

    final codec = await decode(buffer);

    if (loader.cacheScope != _scope) {
      codec.dispose();

      throw const ArtworkLoadException();
    }

    return codec;
  }

  @override
  bool operator ==(Object other) =>
      other is AuthenticatedNetworkImage &&
      other.url == url &&
      other._scope == _scope &&
      other.decodeSize == decodeSize &&
      other.headers['Authorization'] == headers['Authorization'];

  @override
  int get hashCode => Object.hash(url, _scope, decodeSize, headers['Authorization']);
}

/// Frame decoding happens after the codec future completes. Observe the whole
/// completer without adding a listener that would keep off-screen codecs alive.
class _ArtworkImageStreamCompleter extends MultiFrameImageStreamCompleter {
  final VoidCallback onError;
  final VoidCallback onDispose;

  _ArtworkImageStreamCompleter({required super.codec, required this.onError, required this.onDispose})
    : super(scale: 1);

  @override
  void reportError({
    DiagnosticsNode? context,
    required Object exception,
    StackTrace? stack,
    InformationCollector? informationCollector,
    bool silent = false,
  }) {
    onError();
    super.reportError(
      context: context,
      exception: exception,
      stack: stack,
      informationCollector: informationCollector,
      silent: silent,
    );
  }

  @override
  void onDisposed() {
    onDispose();
    super.onDisposed();
  }
}

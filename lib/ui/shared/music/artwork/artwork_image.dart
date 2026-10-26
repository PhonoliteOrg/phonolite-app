import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_scope.dart';

/// One image-source, loading and error policy for music artwork.
/// Album, avatar and banner presentations supply their own frame/fallback.
class ArtworkImage extends StatefulWidget {
  final String? imageUrl;
  final Widget placeholder;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final bool showPlaceholderWhileLoading;
  final int? decodeSize;
  final bool evictWhenUnused;
  final bool retryOnError;

  const ArtworkImage({
    super.key,
    required this.imageUrl,
    required this.placeholder,
    this.headers,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.showPlaceholderWhileLoading = false,
    this.decodeSize,
    this.evictWhenUnused = false,
    this.retryOnError = false,
  });

  @override
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  ImageProvider? _provider;
  ArtworkLoader? _loader;
  String? _providerScope;
  Map<String, String>? _headers;
  Timer? _retry;
  int _attempts = 0;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loader = ArtworkScope.maybeOf(context);

    if (loader != _loader || loader?.cacheScope != _providerScope) {
      _retry?.cancel();
      _attempts = 0;
      _generation++;
      _loader = loader;
      _configure();
    }
  }

  @override
  void didUpdateWidget(ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.decodeSize != widget.decodeSize ||
        _loader?.cacheScope != _providerScope ||
        !mapEquals(_headers, widget.headers)) {
      _retry?.cancel();
      _attempts = 0;
      _generation++;
      _configure();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _configure() {
    _headers = widget.headers == null ? null : Map.of(widget.headers!);
    final path = widget.imageUrl?.trim();
    final loader = _loader;
    _providerScope = loader?.cacheScope;
    if (path == null || path.isEmpty || loader == null) {
      _provider = null;
      return;
    }

    final size = widget.decodeSize;
    final provider = AuthenticatedNetworkImage(path, loader: loader, headers: _headers, decodeSize: size);
    _provider = size == null
        ? provider
        : ResizeImage(provider, width: size, height: size, policy: ResizeImagePolicy.fit);
  }

  void _discard(ImageProvider? provider) {
    if (provider == null) {
      return;
    }
    unawaited(
      provider.obtainKey(ImageConfiguration.empty).then<void>((key) {
        // Other visible consumers may still have a live listener. Remove only
        // the retained cache entry so disposal does not disrupt those images.
        PaintingBinding.instance.imageCache.evict(key, includeLive: false);
      }, onError: (Object error, StackTrace stackTrace) {}),
    );
  }

  void _retryAfterError(Object error) {
    if (!widget.retryOnError ||
        _attempts >= 2 ||
        (_retry?.isActive ?? false) ||
        (error is ArtworkLoadException && [401, 403, 404, 410, 413, 422].contains(error.statusCode))) {
      return;
    }
    final generation = _generation;
    _attempts++;
    final delay = error is ArtworkLoadException && error.retryAfter != null
        ? error.retryAfter!
        : Duration(seconds: _attempts);
    _retry = Timer(delay, () {
      if (!mounted || generation != _generation) {
        return;
      }
      _discard(_provider);
      setState(() => _generation++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return widget.placeholder;
    }
    return Image(
      key: ValueKey(_generation),
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      frameBuilder: widget.showPlaceholderWhileLoading
          ? (context, child, frame, synchronous) => frame == null ? widget.placeholder : child
          : null,
      errorBuilder: (context, error, stack) {
        ArtworkErrors.instance.report(widget.imageUrl!, error);
        _retryAfterError(error);
        return widget.placeholder;
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_placeholder.dart';

/// Square album cover with a lettered placeholder.
///
/// List and grid covers decode at their rendered size, bucketed by [ArtworkRequest.thumbnailBucket].
/// Pass `thumbnail: false` where the image must share the full-resolution cache entry that the
/// now-playing artwork preloader prepares.
class AlbumArt extends StatelessWidget {
  final String title;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;
  final Widget? placeholder;
  final BoxFit fit;
  final bool thumbnail;

  const AlbumArt({
    super.key,
    required this.title,
    required this.size,
    this.imageUrl,
    this.headers,
    this.placeholder,
    this.fit = BoxFit.cover,
    this.thumbnail = true,
  });

  /// Largest physical size the thumbnail buckets cover; bigger covers keep the source resolution.
  static const int _maxThumbnailPixels = 512;

  int? _decodeSize(BuildContext context) {
    if (!thumbnail) {
      return null;
    }

    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();

    return pixels > _maxThumbnailPixels ? null : ArtworkRequest.thumbnailBucket(pixels);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Uri.tryParse(imageUrl?.trim() ?? '')?.scheme;

    return SizedBox.square(
      dimension: size,
      child: ArtworkImage(
        imageUrl: imageUrl,
        headers: headers,
        width: size,
        height: size,
        fit: fit,
        decodeSize: _decodeSize(context),
        showPlaceholderWhileLoading: true,
        retryOnError: scheme == 'http' || scheme == 'https',
        placeholder:
            placeholder ??
            ArtworkPlaceholder(
              label: title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?',
              size: size,
              fontSize: size / 3,
            ),
      ),
    );
  }
}

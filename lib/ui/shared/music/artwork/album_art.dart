import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/music/artwork/artwork_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_placeholder.dart';

class AlbumArt extends StatelessWidget {
  final String title;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;
  final Widget? placeholder;
  final BoxFit fit;

  const AlbumArt({
    super.key,
    required this.title,
    required this.size,
    this.imageUrl,
    this.headers,
    this.placeholder,
    this.fit = BoxFit.cover,
  });

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

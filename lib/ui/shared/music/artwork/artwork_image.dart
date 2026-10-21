import 'dart:io';

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/music/artwork/artwork_errors.dart';

/// One image-source, loading and error policy for music artwork.
/// Album, avatar and banner presentations supply their own frame/fallback.
class ArtworkImage extends StatelessWidget {
  final String? imageUrl;
  final Widget placeholder;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final bool showPlaceholderWhileLoading;

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
  });

  @override
  Widget build(BuildContext context) {
    final path = imageUrl?.trim();

    if (path == null || path.isEmpty) {
      return placeholder;
    }

    final uri = Uri.tryParse(path);
    final remote = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final provider = remote ? NetworkImage(path, headers: headers) as ImageProvider : FileImage(File(path));

    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      frameBuilder: showPlaceholderWhileLoading
          ? (context, child, frame, synchronous) => frame == null ? placeholder : child
          : null,
      errorBuilder: (context, error, stack) {
        ArtworkErrors.instance.report(path, error);

        return placeholder;
      },
    );
  }
}

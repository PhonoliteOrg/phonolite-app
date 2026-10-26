import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_image.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_placeholder.dart';
import 'package:phonolite_app/ui/shared/music/artwork/backdrop_color.dart';

class ArtistAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;
  final BoxFit fit;
  final double paddingFraction;
  final bool thumbnail;

  const ArtistAvatar({
    super.key,
    required this.name,
    required this.size,
    this.imageUrl,
    this.headers,
    this.fit = BoxFit.contain,
    this.paddingFraction = artistLogoContainPadding,
    this.thumbnail = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final placeholder = ArtworkPlaceholder(label: initial, size: size, fontSize: size / 2.4, shape: BoxShape.circle);
    final imagePath = imageUrl?.trim();

    if (imagePath == null || imagePath.isEmpty) {
      return placeholder;
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: resolveLogoBackdropColor(imagePath),
        padding: EdgeInsets.all(size * paddingFraction),
        child: ArtworkImage(
          imageUrl: imagePath,
          headers: headers,
          width: size,
          height: size,
          fit: fit,
          placeholder: placeholder,
          decodeSize: thumbnail ? (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 512) : null,
          retryOnError: thumbnail,
        ),
      ),
    );
  }
}

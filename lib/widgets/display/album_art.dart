import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/artwork_errors.dart';
import '../../core/constants.dart';

class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.title,
    required this.size,
    this.imageUrl,
    this.headers,
    this.placeholder,
    this.fit = BoxFit.cover,
  });

  final String title;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;
  final Widget? placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback =
        placeholder ??
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFE581), accentGold],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?',
            style: GoogleFonts.rajdhani(
              color: Colors.black,
              fontSize: size / 3,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    Widget frameBuilder(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) => frame == null ? fallback : child;

    final imagePath = imageUrl?.trim();
    Widget onImageError(BuildContext context, Object error, StackTrace? stack) {
      ArtworkErrors.instance.report(imagePath!, error);
      return fallback;
    }

    final image = imagePath == null || imagePath.isEmpty
        ? fallback
        : _isRemoteImage(imagePath)
        ? Image.network(
            imagePath,
            headers: headers,
            width: size,
            height: size,
            fit: fit,
            frameBuilder: frameBuilder,
            errorBuilder: onImageError,
          )
        : Image.file(
            File(imagePath),
            width: size,
            height: size,
            fit: fit,
            frameBuilder: frameBuilder,
            errorBuilder: onImageError,
          );

    return SizedBox.square(dimension: size, child: image);
  }

  bool _isRemoteImage(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.title,
    required this.size,
    this.imageUrl,
    this.headers,
  });

  final String title;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFFE581),
            accentGold,
          ],
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

    final image = imageUrl == null || imageUrl!.isEmpty
        ? placeholder
        : Image.network(
            imageUrl!,
            headers: headers,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );

    return image;
  }
}

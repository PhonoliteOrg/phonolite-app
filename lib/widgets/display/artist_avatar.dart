import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ui/backdrop_color.dart';

class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.name,
    required this.size,
    this.imageUrl,
    this.headers,
    this.fit = BoxFit.contain,
    this.paddingFraction = artistLogoContainPadding,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;
  final BoxFit fit;
  final double paddingFraction;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
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
        initial,
        style: GoogleFonts.rajdhani(
          color: Colors.black,
          fontSize: size / 2.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) {
      return placeholder;
    }

    final provider = NetworkImage(imageUrl!, headers: headers);
    return ClipOval(
      child: FutureBuilder<Color>(
        future: resolveLogoBackdropColor(provider, imageUrl!),
        builder: (context, snapshot) {
          final backdrop = snapshot.data ?? artistLogoBackdrop;
          return Container(
            width: size,
            height: size,
            color: backdrop,
            padding: EdgeInsets.all(size * paddingFraction),
            child: Image(
              image: provider,
              width: size,
              height: size,
              fit: fit,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          );
        },
      ),
    );
  }
}

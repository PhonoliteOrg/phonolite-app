import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';

/// The shared initial, gold gradient and typography for missing artwork.
class ArtworkPlaceholder extends StatelessWidget {
  final String label;
  final double size;
  final double fontSize;
  final BoxShape shape;

  const ArtworkPlaceholder({
    super.key,
    required this.label,
    required this.size,
    required this.fontSize,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: shape,
      gradient: const LinearGradient(
        colors: [Color(0xFFFFE581), accentGold],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    alignment: Alignment.center,
    child: Text(
      label,
      style: GoogleFonts.rajdhani(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.w700),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

/// Common catalog card arrangement, title design and compact size boost.
class MediaCardBody extends StatelessWidget {
  final Widget artwork;
  final String title;
  final double fontSize;
  final double artworkGap;
  final double? letterSpacing;
  final MainAxisSize mainAxisSize;

  const MediaCardBody({
    super.key,
    required this.artwork,
    required this.title,
    this.fontSize = 16,
    this.artworkGap = 14,
    this.letterSpacing,
    this.mainAxisSize = MainAxisSize.max,
  });

  static double textSize(BuildContext context, double value) =>
      value * ObsidianScale.of(context) * (MediaQuery.sizeOf(context).width < 640 ? 1.2 : 1);

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: mainAxisSize,
      children: [
        artwork,
        SizedBox(height: artworkGap * scale),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.rajdhani(
            color: Colors.white,
            fontSize: textSize(context, fontSize),
            fontWeight: FontWeight.w700,
            letterSpacing: letterSpacing == null ? null : letterSpacing! * scale,
          ),
        ),
      ],
    );
  }
}

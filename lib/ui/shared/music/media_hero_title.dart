import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';

class MediaHeroTitle extends StatelessWidget {
  final String title;
  final double desktopFontSize;
  final double desktopLetterSpacing;

  const MediaHeroTitle({super.key, required this.title, this.desktopFontSize = 42, this.desktopLetterSpacing = 1.4});

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);
    final scale = ObsidianScale.of(context);

    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: ObsidianFonts.display,
        color: Colors.white,
        fontSize: compact ? 24 : desktopFontSize * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: compact ? 0.3 : desktopLetterSpacing * scale,
        height: 1.05,
      ),
    );
  }
}

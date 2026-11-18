import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class PlaybackTechTag extends StatelessWidget {
  final String label;
  final bool highlight;
  final Color? outlineColor;

  const PlaybackTechTag({super.key, required this.label, this.highlight = false, this.outlineColor});

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    final borderColor =
        outlineColor ?? (highlight ? ObsidianPalette.gold.withByteOpacity(0.6) : Colors.white.withByteOpacity(0.1));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(4), vertical: s(0.5)),
      decoration: BoxDecoration(
        color: Colors.white.withByteOpacity(0.05),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: ObsidianFonts.display,
          fontSize: s(9.5),
          fontWeight: FontWeight.w600,
          letterSpacing: s(0.6),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/expandable_summary_text.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';

class MediaHeroSummary extends StatelessWidget {
  final String text;
  final double fontSize;
  final double lineHeight;
  final double collapsedMaxHeight;

  const MediaHeroSummary({
    super.key,
    required this.text,
    this.fontSize = 12,
    this.lineHeight = 1.35,
    this.collapsedMaxHeight = 60,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);

    return ExpandableSummaryText(
      text: text,
      style: TextStyle(
        fontFamily: ObsidianFonts.body,
        color: Colors.white70,
        fontSize: fontSize * scale,
        height: lineHeight,
      ),
      toggleColor: accentGold,
      collapsedMaxHeight: collapsedMaxHeight * scale,
      togglePadding: EdgeInsets.symmetric(vertical: 4 * scale),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/expandable_summary_text.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';

/// The common responsive frame for music detail headers.
/// Background treatment and content are supplied by the album/artist variant.
class MediaHeroFrame extends StatelessWidget {
  final List<Widget> backgroundLayers;
  final Widget child;
  final double minHeight;

  const MediaHeroFrame({super.key, required this.backgroundLayers, required this.child, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);
    final scale = ObsidianScale.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        children: [
          ...backgroundLayers,
          Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : EdgeInsets.fromLTRB(24 * scale, 20 * scale, 20 * scale, 20 * scale),
            child: child,
          ),
        ],
      ),
    );
  }
}

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
      style: GoogleFonts.rajdhani(
        color: Colors.white,
        fontSize: compact ? 24 : desktopFontSize * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: compact ? 0.3 : desktopLetterSpacing * scale,
        height: 1.05,
      ),
    );
  }
}

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
      style: GoogleFonts.poppins(color: Colors.white70, fontSize: fontSize * scale, height: lineHeight),
      toggleColor: accentGold,
      collapsedMaxHeight: collapsedMaxHeight * scale,
      togglePadding: EdgeInsets.symmetric(vertical: 4 * scale),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chamfer_clipper.dart';
import 'obsidian_theme.dart';

enum TechButtonVariant { standard, danger }
enum TechButtonDensity { standard, compact }

class TechButton extends StatelessWidget {
  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = TechButtonVariant.standard,
    this.density = TechButtonDensity.standard,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
  final TechButtonDensity density;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final isDanger = variant == TechButtonVariant.danger;
    final accent = isDanger ? Colors.redAccent : ObsidianPalette.gold;
    final fill = isDanger
        ? Colors.red.withOpacity(0.1)
        : ObsidianPalette.gold.withOpacity(0.1);
    final borderColor = enabled ? accent : accent.withOpacity(0.4);
    final textSize = density == TechButtonDensity.compact ? 12.5 : 14.0;
    final iconSize = density == TechButtonDensity.compact ? 16.0 : 18.0;
    final padding = density == TechButtonDensity.compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final textStyle = GoogleFonts.rajdhani(
      fontSize: textSize,
      fontWeight: FontWeight.w700,
      letterSpacing: density == TechButtonDensity.compact ? 1.1 : 1.2,
      color: enabled ? accent : accent.withOpacity(0.4),
    );

    return ClipPath(
      clipper: const ChamferClipper(cutSize: 10),
      child: Material(
        color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: iconSize, color: textStyle.color),
                    const SizedBox(width: 6),
                  ],
                  Text(label.toUpperCase(), style: textStyle),
                ],
              ),
            ),
          ),
      ),
    );
  }
}

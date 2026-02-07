import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chamfer_clipper.dart';
import 'obsidian_theme.dart';

enum TechButtonVariant { standard, danger }

class TechButton extends StatelessWidget {
  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = TechButtonVariant.standard,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final TechButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final isDanger = variant == TechButtonVariant.danger;
    final accent = isDanger ? Colors.redAccent : ObsidianPalette.gold;
    final fill = isDanger
        ? Colors.red.withOpacity(0.1)
        : ObsidianPalette.gold.withOpacity(0.1);
    final borderColor = enabled ? accent : accent.withOpacity(0.4);
    final textStyle = GoogleFonts.rajdhani(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: enabled ? accent : accent.withOpacity(0.4),
    );

    return ClipPath(
      clipper: const ChamferClipper(cutSize: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: textStyle.color),
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

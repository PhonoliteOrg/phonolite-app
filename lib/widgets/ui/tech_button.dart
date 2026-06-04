import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chamfer_clipper.dart';
import 'obsidian_theme.dart';

enum TechButtonVariant { standard, danger }

enum TechButtonDensity { standard, compact }

enum TechButtonChrome { framed, borderless }

class TechButton extends StatefulWidget {
  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = TechButtonVariant.standard,
    this.density = TechButtonDensity.standard,
    this.chrome = TechButtonChrome.framed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
  final TechButtonDensity density;
  final TechButtonChrome chrome;

  @override
  State<TechButton> createState() => _TechButtonState();
}

class _TechButtonState extends State<TechButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final isDanger = widget.variant == TechButtonVariant.danger;
    final accent = isDanger ? Colors.redAccent : ObsidianPalette.gold;
    final fill = isDanger
        ? Colors.red.withValues(alpha: 0.1)
        : ObsidianPalette.gold.withValues(alpha: 0.1);
    final borderColor = enabled ? accent : accent.withValues(alpha: 0.4);
    final textSize = widget.density == TechButtonDensity.compact ? 12.5 : 14.0;
    final iconSize = widget.density == TechButtonDensity.compact ? 16.0 : 18.0;
    final padding = widget.density == TechButtonDensity.compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final letterSpacing = widget.density == TechButtonDensity.compact
        ? 1.1
        : 1.2;

    if (widget.chrome == TechButtonChrome.borderless) {
      final highlighted = enabled && (_hovered || _pressed);
      final idleColor = enabled
          ? ObsidianPalette.textMuted
          : ObsidianPalette.textMuted.withValues(alpha: 0.6);
      final foreground = highlighted ? accent : idleColor;
      final glowOpacity = !enabled ? 0.0 : (_hovered ? 0.7 : 0.35);
      final shadows = <Shadow>[
        if (highlighted)
          Shadow(color: accent.withValues(alpha: glowOpacity), blurRadius: 10),
      ];
      final textStyle = GoogleFonts.rajdhani(
        fontSize: textSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        color: foreground,
        shadows: shadows,
      );

      return MouseRegion(
        onEnter: enabled ? (_) => _setHovered(true) : null,
        onExit: enabled ? (_) => _setHovered(false) : null,
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: iconSize,
                    color: foreground,
                    shadows: shadows,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(widget.label.toUpperCase(), style: textStyle),
              ],
            ),
          ),
        ),
      );
    }

    final textStyle = GoogleFonts.rajdhani(
      fontSize: textSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: enabled ? accent : accent.withValues(alpha: 0.4),
    );

    return ClipPath(
      clipper: const ChamferClipper(cutSize: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: iconSize, color: textStyle.color),
                  const SizedBox(width: 6),
                ],
                Text(widget.label.toUpperCase(), style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

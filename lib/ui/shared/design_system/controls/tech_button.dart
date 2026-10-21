import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_clipper.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

enum TechButtonVariant { standard, danger }

enum TechButtonDensity { standard, compact }

enum TechButtonChrome { framed, borderless }

class TechButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
  final TechButtonDensity density;
  final TechButtonChrome chrome;
  final bool iconOnly;
  final double? iconOnlySize;
  final String? tooltip;

  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.iconWidget,
    this.variant = TechButtonVariant.standard,
    this.density = TechButtonDensity.standard,
    this.chrome = TechButtonChrome.framed,
    this.iconOnly = false,
    this.iconOnlySize,
    this.tooltip,
    this.onTap,
  }) : assert(icon == null || iconWidget == null),
       assert(iconOnlySize == null || iconOnlySize > 0),
       assert(!iconOnly || icon != null || iconWidget != null);

  @override
  State<TechButton> createState() => _TechButtonState();
}

class _TechButtonState extends State<TechButton> with PointerInteraction<TechButton> {
  @override
  bool get interactionEnabled => widget.onTap != null;

  double _iconOnlySize(bool touchLayout) {
    if (touchLayout) {
      return 48.0;
    }

    return widget.density == TechButtonDensity.compact ? 36.0 : 42.0;
  }

  Widget _buildIcon({required double size, required Color? color, List<Shadow>? shadows}) {
    if (widget.iconWidget != null) {
      return IconTheme.merge(
        data: IconThemeData(size: size, color: color, shadows: shadows),
        child: widget.iconWidget!,
      );
    }

    return Icon(widget.icon, size: size, color: color, shadows: shadows);
  }

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final enabled = widget.onTap != null;
    final isDanger = widget.variant == TechButtonVariant.danger;
    final accent = isDanger ? Colors.redAccent : ObsidianPalette.gold;
    final fill = isDanger ? Colors.red.withValues(alpha: 0.1) : ObsidianPalette.gold.withValues(alpha: 0.1);
    final borderColor = enabled ? accent : accent.withValues(alpha: 0.4);
    final double textSize;

    if (touchLayout) {
      textSize = 16.0;
    } else {
      textSize = widget.density == TechButtonDensity.compact ? 12.5 : 14.0;
    }

    final iconSize = widget.density == TechButtonDensity.compact ? 16.0 : 18.0;
    final padding = widget.density == TechButtonDensity.compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final iconOnlySize = widget.iconOnlySize ?? _iconOnlySize(touchLayout);
    final iconOnlyGlyphSize = widget.density == TechButtonDensity.compact ? 20.0 : 24.0;
    final letterSpacing = widget.density == TechButtonDensity.compact ? 1.1 : 1.2;
    final semanticLabel = widget.tooltip ?? widget.label;

    if (widget.chrome == TechButtonChrome.borderless) {
      final highlighted = enabled && (hovered || pressed);
      final idleColor = enabled ? ObsidianPalette.textMuted : ObsidianPalette.textMuted.withValues(alpha: 0.6);
      final foreground = highlighted ? accent : idleColor;
      final double glowOpacity;

      if (!enabled) {
        glowOpacity = 0.0;
      } else {
        glowOpacity = hovered ? 0.7 : 0.35;
      }

      final shadows = <Shadow>[if (highlighted) Shadow(color: accent.withValues(alpha: glowOpacity), blurRadius: 10)];

      final textStyle = GoogleFonts.rajdhani(
        fontSize: textSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        color: foreground,
        shadows: shadows,
      );

      final child = widget.iconOnly
          ? SizedBox.square(
              dimension: iconOnlySize,
              child: Center(
                child: _buildIcon(size: iconOnlyGlyphSize, color: foreground, shadows: shadows),
              ),
            )
          : Container(
              constraints: touchLayout ? const BoxConstraints(minHeight: 48, minWidth: 48) : null,
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null || widget.iconWidget != null) ...[
                    _buildIcon(size: iconSize, color: foreground, shadows: shadows),
                    const SizedBox(width: 6),
                  ],
                  Text(widget.label.toUpperCase(), style: textStyle),
                ],
              ),
            );

      final button = pointerRegion(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: child);

      if (!widget.iconOnly) {
        return button;
      }

      return Tooltip(
        message: semanticLabel,
        excludeFromSemantics: true,
        child: Semantics(button: true, enabled: enabled, label: semanticLabel, child: button),
      );
    }

    final textStyle = GoogleFonts.rajdhani(
      fontSize: textSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: enabled ? accent : accent.withValues(alpha: 0.4),
    );

    final button = ClipPath(
      clipper: const ChamferClipper(cutSize: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: withButtonHaptic(widget.onTap),
          child: Container(
            constraints: touchLayout ? const BoxConstraints(minHeight: 48, minWidth: 48) : null,
            padding: widget.iconOnly ? EdgeInsets.zero : padding,
            width: widget.iconOnly ? iconOnlySize : null,
            height: widget.iconOnly ? iconOnlySize : null,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: borderColor),
            ),
            child: widget.iconOnly
                ? _buildIcon(size: iconOnlyGlyphSize, color: textStyle.color)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null || widget.iconWidget != null) ...[
                        _buildIcon(size: iconSize, color: textStyle.color),
                        const SizedBox(width: 6),
                      ],
                      Text(widget.label.toUpperCase(), style: textStyle),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!widget.iconOnly) {
      return button;
    }

    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: Semantics(button: true, enabled: enabled, label: semanticLabel, child: button),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button_variant.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

enum TechButtonDensity { standard, compact }

class TechButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
  final TechButtonDensity density;
  final bool iconOnly;
  final double? iconOnlySize;

  /// Places the icon in a fixed-width slot at the end of a labeled button.
  final double? trailingIconWidth;
  final String? tooltip;

  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.iconWidget,
    this.variant = TechButtonVariant.standard,
    this.density = TechButtonDensity.standard,
    this.iconOnly = false,
    this.iconOnlySize,
    this.trailingIconWidth,
    this.tooltip,
    this.onTap,
  }) : assert(icon == null || iconWidget == null),
       assert(iconOnlySize == null || iconOnlySize > 0),
       assert(trailingIconWidth == null || trailingIconWidth > 0 && !iconOnly && (icon != null || iconWidget != null)),
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
    final icon = widget.icon != null || widget.iconWidget != null
        ? _buildIcon(size: widget.iconOnly ? iconOnlyGlyphSize : iconSize, color: foreground, shadows: shadows)
        : null;
    final trailingIconWidth = widget.trailingIconWidth;

    final textStyle = TextStyle(
      fontFamily: ObsidianFonts.display,
      fontSize: textSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: foreground,
      shadows: shadows,
    );

    final child = widget.iconOnly
        ? SizedBox.square(
            dimension: iconOnlySize,
            child: Center(child: icon),
          )
        : Container(
            constraints: touchLayout ? const BoxConstraints(minHeight: 48, minWidth: 48) : null,
            padding: trailingIconWidth == null
                ? padding
                : EdgeInsetsDirectional.fromSTEB(padding.left, padding.top, 0, padding.bottom),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null && trailingIconWidth == null) ...[icon, const SizedBox(width: 6)],
                Text(widget.label.toUpperCase(), style: textStyle),
                if (trailingIconWidth != null)
                  SizedBox(
                    width: trailingIconWidth,
                    child: Center(heightFactor: 1, child: icon),
                  ),
              ],
            ),
          );

    final button = pointerRegion(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      semanticLabel: widget.iconOnly ? semanticLabel : null,
      child: child,
    );

    if (!widget.iconOnly) {
      return button;
    }

    return Tooltip(message: semanticLabel, excludeFromSemantics: true, child: button);
  }
}

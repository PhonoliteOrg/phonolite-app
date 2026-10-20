import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chamfer_clipper.dart';
import 'obsidian_theme.dart';
import '../modals/obsidian_modal_scope.dart';
import 'button_haptics.dart';

enum TechButtonVariant { standard, danger }

enum TechButtonDensity { standard, compact }

enum TechButtonChrome { framed, borderless }

class TechButton extends StatefulWidget {
  const TechButton({
    super.key,
    required this.label,
    this.icon,
    this.iconWidget,
    this.onTap,
    this.variant = TechButtonVariant.standard,
    this.density = TechButtonDensity.standard,
    this.chrome = TechButtonChrome.framed,
    this.iconOnly = false,
    this.iconOnlySize,
    this.tooltip,
  }) : assert(icon == null || iconWidget == null),
       assert(iconOnlySize == null || iconOnlySize > 0),
       assert(!iconOnly || icon != null || iconWidget != null);

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
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final enabled = widget.onTap != null;
    final isDanger = widget.variant == TechButtonVariant.danger;
    final accent = isDanger ? Colors.redAccent : ObsidianPalette.gold;
    final fill = isDanger
        ? Colors.red.withValues(alpha: 0.1)
        : ObsidianPalette.gold.withValues(alpha: 0.1);
    final borderColor = enabled ? accent : accent.withValues(alpha: 0.4);
    final textSize = touchLayout
        ? 16.0
        : widget.density == TechButtonDensity.compact
        ? 12.5
        : 14.0;
    final iconSize = widget.density == TechButtonDensity.compact ? 16.0 : 18.0;
    final padding = widget.density == TechButtonDensity.compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final iconOnlySize =
        widget.iconOnlySize ??
        (touchLayout
            ? 48.0
            : widget.density == TechButtonDensity.compact
            ? 36.0
            : 42.0);
    final iconOnlyGlyphSize = widget.density == TechButtonDensity.compact
        ? 20.0
        : 24.0;
    final letterSpacing = widget.density == TechButtonDensity.compact
        ? 1.1
        : 1.2;
    final semanticLabel = widget.tooltip ?? widget.label;

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
      final child = widget.iconOnly
          ? SizedBox.square(
              dimension: iconOnlySize,
              child: Center(
                child: _buildIcon(
                  size: iconOnlyGlyphSize,
                  color: foreground,
                  shadows: shadows,
                ),
              ),
            )
          : Container(
              constraints: touchLayout
                  ? const BoxConstraints(minHeight: 48, minWidth: 48)
                  : null,
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null || widget.iconWidget != null) ...[
                    _buildIcon(
                      size: iconSize,
                      color: foreground,
                      shadows: shadows,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(widget.label.toUpperCase(), style: textStyle),
                ],
              ),
            );

      final button = MouseRegion(
        onEnter: enabled ? (_) => _setHovered(true) : null,
        onExit: enabled ? (_) => _setHovered(false) : null,
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: withButtonHaptic(widget.onTap),
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          behavior: HitTestBehavior.opaque,
          child: child,
        ),
      );

      if (!widget.iconOnly) {
        return button;
      }

      return Tooltip(
        message: semanticLabel,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: semanticLabel,
          child: button,
        ),
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
            constraints: touchLayout
                ? const BoxConstraints(minHeight: 48, minWidth: 48)
                : null,
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
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel,
        child: button,
      ),
    );
  }

  Widget _buildIcon({
    required double size,
    required Color? color,
    List<Shadow>? shadows,
  }) {
    if (widget.iconWidget != null) {
      return IconTheme.merge(
        data: IconThemeData(size: size, color: color, shadows: shadows),
        child: widget.iconWidget!,
      );
    }
    return Icon(widget.icon, size: size, color: color, shadows: shadows);
  }
}

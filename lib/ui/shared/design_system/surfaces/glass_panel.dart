import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_shapes.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/blur.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double cut;
  final double blur;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? shadowColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.cut = 16,
    this.blur = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.gradient,
    this.borderColor,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedGradient =
        gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withByteOpacity(0.08), Colors.white.withByteOpacity(0.01)],
        );
    final border = borderColor ?? ObsidianPalette.border;
    final shadow = shadowColor ?? Colors.black.withByteOpacity(0.6);

    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: ClipPath(
        clipper: CyberClipper(cut: cut),
        child: maybeBlur(
          sigma: blur,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: resolvedGradient,
              border: Border.all(color: border),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

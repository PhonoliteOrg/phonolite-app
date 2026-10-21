import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianGlassSurface extends StatelessWidget {
  static final ui.ImageFilter _backdropBlur = ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28);
  final Widget child;
  final Color? backgroundColor;
  final ShapeBorder? shape;

  /// Shares blur work with siblings in a [BackdropGroup]. Enable only for
  /// surfaces that do not overlap; stacked dialogs need separate backdrops.
  final bool grouped;

  const ObsidianGlassSurface({super.key, required this.child, this.backgroundColor, this.shape, this.grouped = false});

  @override
  Widget build(BuildContext context) {
    final decoration = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: backgroundColor == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF18181F).withValues(alpha: 0.32),
                  ObsidianPalette.obsidianElevated.withValues(alpha: 0.56),
                  ObsidianPalette.obsidianElevated.withValues(alpha: 0.8),
                ],
                stops: const [0, 0.5, 1],
              )
            : null,
      ),
      child: child,
    );

    final surface = grouped
        ? BackdropFilter.grouped(filter: _backdropBlur, child: decoration)
        : BackdropFilter(filter: _backdropBlur, child: decoration);
    final shape = this.shape;

    return shape == null
        ? ClipRect(child: surface)
        : ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: surface,
          );
  }
}

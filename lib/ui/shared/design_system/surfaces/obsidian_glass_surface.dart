import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/blur.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianGlassSurface extends StatelessWidget {
  static final ui.ImageFilter _backdropBlur = ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36);
  final Widget child;
  final Color? backgroundColor;
  final ShapeBorder? shape;

  /// Shares blur work with siblings in a [BackdropGroup]. Enable only for
  /// surfaces that do not overlap; stacked dialogs need separate backdrops.
  final bool grouped;

  const ObsidianGlassSurface({super.key, required this.child, this.backgroundColor, this.shape, this.grouped = false});

  Color _tint(Color color, {required bool blur}) {
    // Reduce how much unfiltered content shows through while resizing.
    return blur ? color : color.withValues(alpha: 0.8 + color.a * 0.2);
  }

  @override
  Widget build(BuildContext context) {
    final blur = !BackdropBlurResizeSuspension.isSuspended(context);
    final backgroundColor = this.backgroundColor;
    final decoration = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor == null ? null : _tint(backgroundColor, blur: blur),
        gradient: backgroundColor == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _tint(const Color(0xFF18181F).withValues(alpha: 0.72), blur: blur),
                  _tint(ObsidianPalette.obsidianElevated.withValues(alpha: 0.75), blur: blur),
                  _tint(ObsidianPalette.obsidianElevated.withValues(alpha: 0.78), blur: blur),
                ],
                stops: const [0, 0.5, 1],
              )
            : null,
      ),
      child: child,
    );

    final surface = grouped
        ? BackdropFilter.grouped(filter: _backdropBlur, enabled: blur, child: decoration)
        : BackdropFilter(filter: _backdropBlur, enabled: blur, child: decoration);
    final shape = this.shape;

    return shape == null
        ? ClipRect(child: surface)
        : ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: surface,
          );
  }
}

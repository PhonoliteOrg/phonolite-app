import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'obsidian_theme.dart';

class ObsidianGlassSurface extends StatelessWidget {
  const ObsidianGlassSurface({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  static final _backdropBlur = ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28);

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: _backdropBlur,
        child: DecoratedBox(
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
        ),
      ),
    );
  }
}

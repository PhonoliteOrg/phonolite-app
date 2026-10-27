import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/desktop_playback_layout.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';

/// Fits the complete desktop player, including its footer and margins, once.
class DesktopPlaybackFrame extends StatelessWidget {
  final DesktopPlaybackLayout layout;
  final Widget child;

  const DesktopPlaybackFrame({super.key, required this.layout, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: layout.width,
    height: layout.height,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: layout.canvasWidth,
        height: DesktopPlaybackLayout.canvasHeight,
        child: Padding(
          padding: DesktopPlaybackLayout.margin,
          child: ObsidianGlassSurface(
            child: Padding(padding: DesktopPlaybackLayout.panelPadding, child: child),
          ),
        ),
      ),
    ),
  );
}

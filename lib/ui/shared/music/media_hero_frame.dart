import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';

/// The common responsive frame for music detail headers.
/// Background treatment and content are supplied by the album/artist variant.
class MediaHeroFrame extends StatelessWidget {
  final List<Widget> backgroundLayers;
  final Widget child;
  final double minHeight;

  const MediaHeroFrame({super.key, required this.backgroundLayers, required this.child, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);
    final scale = ObsidianScale.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        children: [
          ...backgroundLayers,
          Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : EdgeInsets.fromLTRB(24 * scale, 20 * scale, 20 * scale, 20 * scale),
            child: child,
          ),
        ],
      ),
    );
  }
}

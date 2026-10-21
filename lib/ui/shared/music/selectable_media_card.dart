import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hover_card.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';

/// Owns selection, deletion feedback and hover behavior for catalog cards.
/// The content builder supplies only the particular artwork and label layout.
class SelectableMediaCard extends StatelessWidget {
  final MediaSelection selection;
  final Widget Function(BuildContext, BoxConstraints, bool) contentBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SelectableMediaCard({
    super.key,
    required this.selection,
    required this.contentBuilder,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final tap = selection.tapAction(onTap);

    return Semantics(
      selected: selection.selectionMode ? selection.selected : null,
      enabled: selection.selectionMode ? tap != null : null,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selection.selectionMode
              ? Border.all(color: selection.selected ? ObsidianPalette.gold : ObsidianPalette.border, width: 1.5)
              : null,
        ),
        child: ObsidianHoverCard(
          padding: EdgeInsets.all(14 * scale),
          onTap: tap,
          onLongPress: selection.longPressAction(onLongPress),
          splashColor: ObsidianPalette.gold.withValues(alpha: 0.2),
          childBuilder: (context, hovered) => LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.passthrough,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selection.opacity,
                  child: contentBuilder(context, constraints, hovered),
                ),
                if (selection.isDeleting)
                  Positioned(
                    right: 4 * scale,
                    bottom: 4 * scale,
                    child: SizedBox.square(
                      dimension: 24 * scale,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ObsidianPalette.gold,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

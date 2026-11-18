import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_tap_target.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_fonts.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class PlaybackQualityBadge extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const PlaybackQualityBadge({super.key, required this.label, required this.onTap});

  @override
  State<PlaybackQualityBadge> createState() => PlaybackQualityBadgeState();
}

class PlaybackQualityBadgeState extends State<PlaybackQualityBadge> {
  static const Duration _transition = Duration(milliseconds: 200);

  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }

    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    final usesTouchTargets = ObsidianModalScope.usesTouchTargets(context);
    final enabled = widget.onTap != null;
    final active = enabled && _hovered;
    final textColor = enabled ? ObsidianPalette.gold : ObsidianPalette.textMuted;

    return ObsidianTapTarget(
      onTap: widget.onTap,
      onHover: _setHovered,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: usesTouchTargets ? 48 : 0, minHeight: usesTouchTargets ? 48 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: _transition,
              curve: Curves.easeOut,
              alignment: Alignment.center,
              constraints: BoxConstraints(minHeight: s(36)),
              padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(6)),
              child: AnimatedDefaultTextStyle(
                duration: _transition,
                curve: Curves.easeOut,
                style: TextStyle(
                  fontFamily: ObsidianFonts.display,
                  fontSize: s(13),
                  fontWeight: FontWeight.w600,
                  letterSpacing: s(1.2),
                  color: textColor,
                  shadows: [if (active) Shadow(color: ObsidianPalette.gold.withValues(alpha: 0.7), blurRadius: s(10))],
                ),
                child: Text(widget.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

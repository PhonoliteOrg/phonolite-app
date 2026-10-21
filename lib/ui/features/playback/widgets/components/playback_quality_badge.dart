import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

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
    double s(double value) => playbackScaled(context, value);

    final usesTouchTargets = ObsidianModalScope.usesTouchTargets(context);
    final enabled = widget.onTap != null;
    final active = enabled && _hovered;
    final textColor = enabled ? ObsidianPalette.gold : ObsidianPalette.textMuted;

    return MouseRegion(
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled ? (_) => _setHovered(false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: withButtonHaptic(widget.onTap),
        behavior: HitTestBehavior.opaque,
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
                  style: GoogleFonts.rajdhani(
                    fontSize: s(13),
                    fontWeight: FontWeight.w600,
                    letterSpacing: s(1.2),
                    color: textColor,
                    shadows: [
                      if (active) Shadow(color: ObsidianPalette.gold.withValues(alpha: 0.7), blurRadius: s(10)),
                    ],
                  ),
                  child: Text(widget.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Keeps secondary header information available without crowding phone layouts.
class CompactHeroDetails extends StatefulWidget {
  final String label;
  final Widget child;

  const CompactHeroDetails({super.key, required this.label, required this.child});

  @override
  State<CompactHeroDetails> createState() => _CompactHeroDetailsState();
}

class _CompactHeroDetailsState extends State<CompactHeroDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          expanded: _expanded,
          child: TextButton(
            onPressed: withButtonHaptic(() => setState(() => _expanded = !_expanded)),
            style: TextButton.styleFrom(
              foregroundColor: ObsidianPalette.textMuted,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label),
                const SizedBox(width: 4),
                RotatedBox(quarterTurns: _expanded ? 2 : 0, child: const Icon(PhonoliteIcons.chevronDown, size: 14)),
              ],
            ),
          ),
        ),
        if (_expanded) widget.child,
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';

class CommandLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const CommandLinkButton({super.key, required this.label, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: withButtonHaptic(enabled ? onTap : null),
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return accentGold.withValues(alpha: 0.4);
            }

            if (states.contains(WidgetState.pressed)) {
              return accentGold.withValues(alpha: 0.75);
            }

            if (states.contains(WidgetState.hovered)) {
              return accentGold.withValues(alpha: 0.9);
            }

            return accentGold;
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          minimumSize: WidgetStateProperty.all(const Size(0, 40)),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: WidgetStateProperty.all(const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
          textStyle: WidgetStateProperty.all(GoogleFonts.rajdhani(fontWeight: FontWeight.w600, letterSpacing: 1.6)),
        ),
        icon: const Icon(PhonoliteIcons.chevronLeft, size: 18),
        label: Text(label.toUpperCase()),
      ),
    );
  }
}

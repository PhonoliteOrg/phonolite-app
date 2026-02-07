import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

class CommandLinkButton extends StatelessWidget {
  const CommandLinkButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.resolveWith<Color>(
            (states) {
              if (states.contains(MaterialState.pressed)) {
                return accentGold.withOpacity(0.75);
              }
              if (states.contains(MaterialState.hovered)) {
                return accentGold.withOpacity(0.9);
              }
              return accentGold;
            },
          ),
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          padding: MaterialStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          minimumSize: MaterialStateProperty.all(const Size(0, 40)),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: MaterialStateProperty.all(
            const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          textStyle: MaterialStateProperty.all(
            GoogleFonts.rajdhani(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
            ),
          ),
        ),
        icon: const Icon(Icons.chevron_left, size: 18),
        label: Text(label.toUpperCase()),
      ),
    );
  }
}

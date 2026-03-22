import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ui/gradient_text.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key, required this.moduleCount, this.trailing});

  final int moduleCount;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GradientText(
            'LIBRARY',
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF2A8), accentGold],
            ),
            style: GoogleFonts.rajdhani(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          Padding(padding: const EdgeInsets.only(top: 10), child: trailing!),
        ],
      ],
    );
  }
}

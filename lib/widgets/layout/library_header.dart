import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ui/gradient_text.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key, required this.moduleCount});

  final int moduleCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GradientText(
          'LIBRARY',
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFFF2A8),
              accentGold,
            ],
          ),
          style: GoogleFonts.rajdhani(
            fontSize: 56,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }
}

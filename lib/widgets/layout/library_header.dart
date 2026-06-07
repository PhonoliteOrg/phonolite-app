import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ui/gradient_text.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.moduleCount,
    this.trailing,
    this.title = 'LIBRARY',
  });

  final int moduleCount;
  final Widget? trailing;
  final String title;

  static const double _compactWidth = 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < _compactWidth;
        final titleText = GradientText(
          title,
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF2A8), accentGold],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.rajdhani(
            fontSize: isCompact ? 36 : 56,
            fontWeight: FontWeight.w700,
            letterSpacing: isCompact ? 0.9 : 2.2,
            height: 1.0,
          ),
        );

        return Row(
          crossAxisAlignment: isCompact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: titleText),
            if (trailing != null) ...[
              SizedBox(width: isCompact ? 10 : 16),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}

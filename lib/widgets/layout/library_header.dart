import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.moduleCount,
    this.trailing,
    this.title = 'LIBRARY',
    this.maxLines = 1,
    this.shrinkTitleToFit = false,
  });

  final int moduleCount;
  final Widget? trailing;
  final String title;
  final int maxLines;
  final bool shrinkTitleToFit;

  static const double _compactWidth = 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < _compactWidth;
        final titleText = Text(
          title,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.rajdhani(
            color: accentGold,
            fontSize: isCompact ? 36 : 56,
            fontWeight: FontWeight.w700,
            letterSpacing: isCompact ? 0.9 : 2.2,
            height: 1.0,
          ),
        );

        return ConstrainedBox(
          // Match the toolbar height even on pages without header actions.
          constraints: BoxConstraints(minHeight: isCompact ? 38 : 56),
          child: Row(
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: shrinkTitleToFit
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: titleText,
                      )
                    : titleText,
              ),
              if (trailing != null) ...[
                SizedBox(width: isCompact ? 10 : 16),
                trailing!,
              ],
            ],
          ),
        );
      },
    );
  }
}

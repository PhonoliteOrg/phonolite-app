import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shell/toolbars/base_page_toolbar.dart';

class LibraryHeader extends BasePageToolbar {
  static const double _compactWidth = 560;

  final Widget? trailing;
  final String title;
  final int maxLines;
  final bool shrinkTitleToFit;

  const LibraryHeader({
    super.key,
    this.trailing,
    this.title = 'LIBRARY',
    this.maxLines = 1,
    this.shrinkTitleToFit = false,
  });

  @override
  Widget titleContent(BuildContext context, BoxConstraints constraints) {
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

    return shrinkTitleToFit
        ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: titleText)
        : titleText;
  }

  @override
  Widget? trailingActions(BuildContext context, BoxConstraints constraints) => trailing;

  @override
  double contentSpacing(BuildContext context, BoxConstraints constraints) =>
      constraints.maxWidth < _compactWidth ? 10 : 16;

  @override
  CrossAxisAlignment contentAlignment(BuildContext context, BoxConstraints constraints) =>
      constraints.maxWidth < _compactWidth ? CrossAxisAlignment.center : CrossAxisAlignment.start;

  @override
  BoxConstraints contentConstraints(BuildContext context, BoxConstraints constraints) =>
      BoxConstraints(minHeight: constraints.maxWidth < _compactWidth ? 38 : 56);
}

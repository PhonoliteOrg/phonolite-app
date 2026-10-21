import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';

/// A library section heading uses the same gutter and title presentation.
class LibrarySectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const LibrarySectionHeading({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => PageSliverBox(
    top: 8,
    bottom: 16,
    child: ObsidianSectionHeader(title: title, subtitle: subtitle, trailing: trailing),
  );
}

/// Status copy for both local and connected library search sections.
class LibraryStatusSliver extends StatelessWidget {
  final String message;

  const LibraryStatusSliver({super.key, required this.message});

  @override
  Widget build(BuildContext context) => PageSliverBox(
    top: 24,
    child: Text(
      message,
      style: GoogleFonts.rajdhani(color: Colors.white54, fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w600),
    ),
  );
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shell/page_sliver_box.dart';

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

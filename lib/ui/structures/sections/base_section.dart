import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';

/// Consistent heading and spacing for a section of ordinary box widgets.
abstract class BaseSection extends StatelessWidget {
  const BaseSection({super.key});

  @protected
  String get sectionTitle;

  @protected
  double get headingSpacing => 12;

  @protected
  List<Widget> sectionContent(BuildContext context);

  @protected
  Widget sectionHeader(BuildContext context) => ObsidianSectionHeader(title: sectionTitle);

  @override
  @nonVirtual
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionHeader(context),
      SizedBox(height: headingSpacing),
      ...sectionContent(context),
    ],
  );
}

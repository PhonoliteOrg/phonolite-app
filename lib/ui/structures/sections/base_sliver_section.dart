import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';

/// Common optional heading and padding for a sliver-based collection section.
abstract class BaseSliverSection extends StatelessWidget {
  const BaseSliverSection({super.key});

  @protected
  String? get sectionTitle;

  @protected
  EdgeInsetsGeometry get headerPadding => const EdgeInsets.fromLTRB(20, 20, 20, 8);

  @protected
  EdgeInsetsGeometry get contentPadding => const EdgeInsets.fromLTRB(20, 8, 20, 24);

  @protected
  Widget sectionSliver(BuildContext context);

  @protected
  Widget sectionHeader(BuildContext context, String title) => ObsidianSectionHeader(title: title);

  @override
  @nonVirtual
  Widget build(BuildContext context) {
    final sectionTitle = this.sectionTitle;

    return SliverMainAxisGroup(
      slivers: [
        if (sectionTitle != null)
          SliverPadding(
            padding: headerPadding,
            sliver: SliverToBoxAdapter(child: sectionHeader(context, sectionTitle)),
          ),
        SliverPadding(padding: contentPadding, sliver: sectionSliver(context)),
      ],
    );
  }
}

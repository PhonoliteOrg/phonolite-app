import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Searchable selection frame; consumers supply choices and selection policy.
class SelectionSliverSection extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String hintText;
  final String summary;
  final VoidCallback onSearch;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;
  final Widget sliver;

  const SelectionSliverSection({
    super.key,
    required this.title,
    required this.controller,
    required this.hintText,
    required this.summary,
    required this.onSearch,
    required this.onSelectAll,
    required this.onClear,
    required this.sliver,
  });

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: EdgeInsets.all(isCompactListWidth(context) ? 12 : 20),
    sliver: SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ObsidianSectionHeader(title: title),
              const SizedBox(height: 16),
              SearchHud(controller: controller, hintText: hintText, height: 48, onSubmit: onSearch, onClear: onSearch),
              const SizedBox(height: 12),
              SelectionSummaryActions(summary: summary, onSelectAll: onSelectAll, onClear: onClear),
              const SizedBox(height: 12),
            ],
          ),
        ),
        sliver,
      ],
    ),
  );
}

/// Common selection summary/actions adapt independently of the choice content.
class SelectionSummaryActions extends StatelessWidget {
  final String summary;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;

  const SelectionSummaryActions({super.key, required this.summary, required this.onSelectAll, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final count = Text(
      summary,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TechButton(
          label: 'Select all',
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onSelectAll,
        ),
        TechButton(
          label: 'Clear',
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onClear,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 480
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [count, const SizedBox(height: 8), actions])
          : Row(
              children: [
                Expanded(child: count),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }
}

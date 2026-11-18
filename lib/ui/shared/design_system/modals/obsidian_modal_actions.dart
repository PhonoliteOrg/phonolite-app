import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_style.dart';

/// Keeps dismiss actions before the primary action and wraps on narrow screens.
class ObsidianModalActions extends StatelessWidget {
  final List<Widget> children;

  const ObsidianModalActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: ObsidianModalStyle.actionSpacing,
      overflowSpacing: ObsidianModalStyle.actionSpacing,
      children: children,
    );
  }
}

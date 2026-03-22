import 'package:flutter/material.dart';

import 'obsidian_widgets.dart';

class CollectionViewToggleButton extends StatelessWidget {
  const CollectionViewToggleButton({
    super.key,
    required this.isListView,
    required this.onPressed,
    this.semanticLabel = 'Collection view',
    this.showListTooltip = 'Show list',
    this.showCardTooltip = 'Show cards',
  });

  final bool isListView;
  final VoidCallback onPressed;
  final String semanticLabel;
  final String showListTooltip;
  final String showCardTooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: isListView,
      label: semanticLabel,
      child: ObsidianNavIcon(
        icon: const Icon(Icons.view_agenda_rounded),
        isSelected: isListView,
        onTap: onPressed,
        size: 40,
        iconSize: 22,
      ),
    );
  }
}

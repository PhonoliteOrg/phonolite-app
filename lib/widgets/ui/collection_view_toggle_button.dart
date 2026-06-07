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
    this.iconSize = 26,
  });

  final bool isListView;
  final VoidCallback onPressed;
  final String semanticLabel;
  final String showListTooltip;
  final String showCardTooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isListView ? showCardTooltip : showListTooltip,
      child: Semantics(
        button: true,
        toggled: isListView,
        label: semanticLabel,
        child: ObsidianHudIconButton(
          icon: Icons.view_agenda_rounded,
          size: iconSize,
          isActive: isListView,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

class CollectionViewToggleButton extends StatelessWidget {
  final bool isListView;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String showListTooltip;
  final String showCardTooltip;
  final double iconSize;

  const CollectionViewToggleButton({
    super.key,
    required this.isListView,
    required this.onPressed,
    this.semanticLabel = 'Collection view',
    this.showListTooltip = 'Show list',
    this.showCardTooltip = 'Show cards',
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isListView ? showCardTooltip : showListTooltip,
      child: Semantics(
        button: true,
        toggled: isListView,
        label: semanticLabel,
        child: ObsidianHudIconButton(
          icon: PhonoliteIcons.rows3,
          size: iconSize,
          isActive: isListView,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

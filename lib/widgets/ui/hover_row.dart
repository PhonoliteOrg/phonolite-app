import 'package:flutter/material.dart';

import 'obsidian_theme.dart';

class ObsidianHoverRow extends StatefulWidget {
  const ObsidianHoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.borderColor = ObsidianPalette.gold,
    this.isActive = false,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color borderColor;
  final bool isActive;
  final bool enabled;

  @override
  State<ObsidianHoverRow> createState() => _ObsidianHoverRowState();
}

class _ObsidianHoverRowState extends State<ObsidianHoverRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isActive || _hovered;
    final borderColor = highlight ? widget.borderColor : Colors.transparent;
    final background = _hovered
        ? LinearGradient(
            colors: [
              Colors.white.withOpacity(0.06),
              Colors.transparent,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : null;
    final enabled = widget.enabled && widget.onTap != null;
    final cursor =
        enabled ? SystemMouseCursors.click : SystemMouseCursors.basic;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: cursor,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: borderColor, width: 2)),
              gradient: background,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

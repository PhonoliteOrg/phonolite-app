import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_supports_hover.dart';

typedef ObsidianHoverWidgetBuilder = Widget Function(BuildContext context, bool hovered);

class ObsidianHoverBuilder extends StatefulWidget {
  final ObsidianHoverWidgetBuilder builder;
  final MouseCursor cursor;
  final bool? enableHover;

  const ObsidianHoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.basic,
    this.enableHover,
  });

  @override
  State<ObsidianHoverBuilder> createState() => _ObsidianHoverBuilderState();
}

class _ObsidianHoverBuilderState extends State<ObsidianHoverBuilder> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }

    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enableHover ?? obsidianSupportsHover();
    final content = widget.builder(context, _hovered);

    if (!enabled) {
      return content;
    }

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: content,
    );
  }
}

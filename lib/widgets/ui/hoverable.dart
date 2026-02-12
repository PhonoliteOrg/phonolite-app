import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool obsidianSupportsHover() {
  return kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

typedef ObsidianHoverWidgetBuilder = Widget Function(
  BuildContext context,
  bool hovered,
);

class ObsidianHoverBuilder extends StatefulWidget {
  const ObsidianHoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.basic,
    this.enableHover,
  });

  final ObsidianHoverWidgetBuilder builder;
  final MouseCursor cursor;
  final bool? enableHover;

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

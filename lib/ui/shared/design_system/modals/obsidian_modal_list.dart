import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class ObsidianModalList extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollPhysics? physics;

  const ObsidianModalList({super.key, required this.itemCount, required this.itemBuilder, this.physics});

  @override
  State<ObsidianModalList> createState() => _ObsidianModalListState();
}

class _ObsidianModalListState extends State<ObsidianModalList> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This list owns its always-visible thumb, including on desktop.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _controller,
          physics: widget.physics,
          padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
          separatorBuilder: (context, index) =>
              Divider(height: 1, color: ObsidianPalette.textMuted.withByteOpacity(0.25)),
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}

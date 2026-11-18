import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_frame.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_sheet_handle.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';

class ObsidianModalSurface extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerActions;
  final bool showDragHandle;

  const ObsidianModalSurface({
    super.key,
    required this.title,
    required this.child,
    this.headerActions,
    this.showDragHandle = false,
  });

  Widget _buildSurface(BuildContext context) {
    final heading = Text(
      title,
      textAlign: TextAlign.left,
      maxLines: headerActions == null ? null : 2,
      overflow: headerActions == null ? null : TextOverflow.ellipsis,
    );

    return ObsidianGlassSurface(
      child: SafeArea(
        top: !showDragHandle,
        child: Column(
          children: [
            if (showDragHandle) const ObsidianSheetHandle(),
            Expanded(
              child: ObsidianModalFrame(
                title: headerActions == null
                    ? Align(alignment: Alignment.centerLeft, child: heading)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: heading),
                          Padding(padding: const EdgeInsets.only(left: 8), child: headerActions!),
                        ],
                      ),
                content: child,
                actions: [ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).maybePop())],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildSurface);
}

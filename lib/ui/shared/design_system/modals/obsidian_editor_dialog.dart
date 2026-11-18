import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/modal_dismiss_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_frame.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';

/// Editor fields receive the width available inside the dialog's content padding.
class ObsidianEditorDialog extends StatelessWidget {
  final String title;
  final bool saving;
  final String dismissLabel;
  final Widget Function(BuildContext context, double contentWidth) contentBuilder;
  final List<Widget> actions;

  const ObsidianEditorDialog({
    super.key,
    required this.title,
    required this.saving,
    required this.contentBuilder,
    required this.actions,
    this.dismissLabel = 'Close',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: ObsidianModalScope(
        builder: (context) {
          final size = MediaQuery.sizeOf(context);
          final insets = ObsidianModalScope.insetsOf(context);
          final width = (size.width - insets.horizontal).clamp(0.0, 760.0).toDouble();
          final maxHeight =
              (size.height -
                      insets.vertical -
                      MediaQuery.viewInsetsOf(context).vertical -
                      MediaQuery.paddingOf(context).vertical)
                  .clamp(0.0, double.infinity)
                  .toDouble();
          return ObsidianDialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SizedBox(
                width: width,
                child: ObsidianModalFrame(
                  title: Text(title),
                  scrollable: true,
                  content: LayoutBuilder(
                    builder: (context, constraints) => contentBuilder(context, constraints.maxWidth),
                  ),
                  actions: [
                    ModalDismissButton(label: dismissLabel, enabled: !saving),
                    ...actions,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

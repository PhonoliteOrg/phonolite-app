import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';

/// Shared editor framing: fixed title/actions, scrollable content and keyboard
/// clearance. Editor variants supply their fields and functional callbacks.
class ObsidianEditorDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final double width;

  const ObsidianEditorDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        (MediaQuery.sizeOf(context).height -
                ObsidianModalScope.insetsOf(context).vertical -
                MediaQuery.viewInsetsOf(context).vertical -
                MediaQuery.paddingOf(context).vertical)
            .clamp(0.0, double.infinity);

    return ObsidianDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: ObsidianModalStyle.titlePadding,
                child: DefaultTextStyle.merge(style: ObsidianModalStyle.titleStyle(context), child: title),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: ObsidianModalStyle.contentPadding,
                    child: DefaultTextStyle.merge(style: ObsidianModalStyle.bodyStyle(context), child: content),
                  ),
                ),
              ),
              Padding(
                padding: ObsidianModalStyle.actionsPadding,
                child: ObsidianModalActions(children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

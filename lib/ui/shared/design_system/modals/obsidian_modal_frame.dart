import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_actions.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_style.dart';

/// A fixed title and actions around either a scrolling form or a full-height panel.
class ObsidianModalFrame extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final bool scrollable;

  const ObsidianModalFrame({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: ObsidianModalStyle.contentPadding,
      child: DefaultTextStyle.merge(style: ObsidianModalStyle.bodyStyle(context), child: content),
    );
    return Column(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: ObsidianModalStyle.titlePadding,
          child: DefaultTextStyle.merge(style: ObsidianModalStyle.titleStyle(context), child: title),
        ),
        if (scrollable) Flexible(child: SingleChildScrollView(child: body)) else Expanded(child: body),
        Padding(
          padding: ObsidianModalStyle.actionsPadding,
          child: ObsidianModalActions(children: actions),
        ),
      ],
    );
  }
}

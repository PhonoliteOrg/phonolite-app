import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/command_link_button.dart';
import 'package:phonolite_app/ui/shell/toolbars/base_page_toolbar.dart';

class DetailActionHeader extends BasePageToolbar {
  final String backLabel;
  final VoidCallback onBack;
  final Widget? actions;
  final bool backEnabled;

  const DetailActionHeader({
    super.key,
    required this.backLabel,
    required this.onBack,
    this.actions,
    this.backEnabled = true,
  });

  @override
  bool get expandsActions => true;

  @override
  Widget leadingContent(BuildContext context, BoxConstraints constraints) =>
      CommandLinkButton(label: backLabel, onTap: onBack, enabled: backEnabled);

  @override
  Widget? trailingActions(BuildContext context, BoxConstraints constraints) => actions == null
      ? null
      : Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: actions!,
          ),
        );
}

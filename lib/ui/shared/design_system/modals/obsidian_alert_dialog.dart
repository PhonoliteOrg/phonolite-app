import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/modal_dismiss_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_style.dart';

/// Retains Flutter's alert layout, text scaling, and accessibility semantics.
class ObsidianAlertDialog extends AlertDialog {
  const ObsidianAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.iconColor,
    super.title,
    super.titlePadding = ObsidianModalStyle.titlePadding,
    super.titleTextStyle,
    super.content,
    super.contentPadding = ObsidianModalStyle.contentPadding,
    super.contentTextStyle,
    super.actions = const [ModalDismissButton()],
    super.actionsPadding = ObsidianModalStyle.actionsPadding,
    super.actionsAlignment = MainAxisAlignment.end,
    super.actionsOverflowAlignment = OverflowBarAlignment.end,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing = ObsidianModalStyle.actionSpacing,
    super.buttonPadding = const EdgeInsets.symmetric(horizontal: 8),
    super.semanticLabel,
    super.insetPadding = ObsidianModalStyle.insetPadding,
    super.shape,
    super.alignment,
    super.constraints,
    super.scrollable,
  });

  Widget _buildAlert(BuildContext context) {
    final dialog = super.build(context) as Dialog;

    return ObsidianDialog(
      insetPadding: dialog.insetPadding,
      shape: dialog.shape,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: dialog.child,
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildAlert);
}

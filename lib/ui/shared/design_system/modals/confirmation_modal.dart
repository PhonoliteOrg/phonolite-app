import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button_variant.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_dismiss_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_alert_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

class ConfirmationModal extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final TechButtonVariant confirmVariant;

  const ConfirmationModal({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Yes',
    this.cancelLabel = 'Cancel',
    this.confirmVariant = TechButtonVariant.danger,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Yes',
    String cancelLabel = 'Cancel',
    TechButtonVariant confirmVariant = TechButtonVariant.danger,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmationModal(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmVariant: confirmVariant,
      ),
    );

    return result ?? false;
  }

  Widget _buildDialog(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 420.0).toDouble();

    return ObsidianAlertDialog(
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: dialogWidth,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted, height: 1.4),
        ),
      ),
      actions: [
        ModalDismissButton(label: cancelLabel, result: false),
        ModalActionButton(
          label: confirmLabel,
          variant: confirmVariant,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildDialog);
}

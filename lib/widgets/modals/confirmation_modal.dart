import 'package:flutter/material.dart';

import '../ui/obsidian_theme.dart';
import '../ui/tech_button.dart';

class ConfirmationModal extends StatelessWidget {
  const ConfirmationModal({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Yes',
    this.cancelLabel = 'Cancel',
    this.confirmVariant = TechButtonVariant.danger,
    this.actionChrome = TechButtonChrome.framed,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final TechButtonVariant confirmVariant;
  final TechButtonChrome actionChrome;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Yes',
    String cancelLabel = 'Cancel',
    TechButtonVariant confirmVariant = TechButtonVariant.danger,
    TechButtonChrome actionChrome = TechButtonChrome.framed,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmationModal(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmVariant: confirmVariant,
        actionChrome: actionChrome,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width - 48)
        .clamp(0.0, 420.0)
        .toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(title),
      content: SizedBox(
        width: dialogWidth,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ObsidianPalette.textMuted,
            height: 1.4,
          ),
        ),
      ),
      actions: [
        if (actionChrome == TechButtonChrome.borderless)
          TechButton(
            label: cancelLabel,
            density: TechButtonDensity.compact,
            chrome: actionChrome,
            onTap: () => Navigator.of(context).pop(false),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
        TechButton(
          label: confirmLabel,
          density: TechButtonDensity.compact,
          variant: confirmVariant,
          chrome: actionChrome,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

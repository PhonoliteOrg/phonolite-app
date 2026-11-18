import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';

class ModalDismissButton<T> extends StatelessWidget {
  final String label;
  final T? result;
  final bool enabled;

  const ModalDismissButton({super.key, this.label = 'Close', this.result, this.enabled = true});

  @override
  Widget build(BuildContext context) =>
      ModalActionButton(label: label, onPressed: enabled ? () => Navigator.of(context).pop<T>(result) : null);
}

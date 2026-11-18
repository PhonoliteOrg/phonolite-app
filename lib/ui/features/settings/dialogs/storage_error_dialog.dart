import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_alert_dialog.dart';

Future<void> settingsShowStorageError(BuildContext context, {required String title, required String message}) async {
  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => ObsidianAlertDialog(title: Text(title), content: Text(message)),
  );
}

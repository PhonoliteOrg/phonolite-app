import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/dialogs/storage_error_dialog.dart';

Future<void> settingsOpenStorageDirectory(BuildContext context, String path) async {
  final opened = await SettingsController.instance.openStorageDirectory(path);

  if (!opened && context.mounted) {
    await settingsShowStorageError(
      context,
      title: 'Could not open folder',
      message: 'Could not open this folder in your file manager:\n$path',
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/dialogs/storage_error_dialog.dart';

Future<void> settingsResetLogsStorage(BuildContext context) async {
  final reset = await SettingsController.instance.resetLogsStorage();

  if (!reset && context.mounted) {
    await settingsShowStorageError(
      context,
      title: 'Could not reset logs storage',
      message: 'Could not restore the default log folder. Your current logs have been kept.',
    );
  }
}

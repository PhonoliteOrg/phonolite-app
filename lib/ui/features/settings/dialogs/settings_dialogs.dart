import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/dialogs/storage_path_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';

bool settingsUsesManagedOfflineStoragePaths(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.iOS;
}

void settingsOpenStoragePathDialog(
  BuildContext context, {
  required String title,
  required String initialPath,
  required bool isDefault,
  required Future<void> Function(String? path) onSave,
}) {
  showDialog<void>(
    context: context,
    builder: (context) =>
        StoragePathDialog(title: title, initialPath: initialPath, isDefault: isDefault, onSave: onSave),
  );
}

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

Future<void> settingsShowStorageError(BuildContext context, {required String title, required String message}) async {
  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => ObsidianAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).pop())],
    ),
  );
}

Future<void> settingsConfirmResetOfflineData(BuildContext context, AppController controller) async {
  final usesManagedPaths = settingsUsesManagedOfflineStoragePaths(context);
  final confirmed = await ConfirmationModal.show(
    context,
    title: 'Reset local data',
    message: usesManagedPaths
        ? 'Delete downloaded tracks, artwork, local metadata, local database files, and logs from this device? Local storage will remain managed automatically on this device.'
        : 'Delete downloaded tracks, artwork, local metadata, local database files, and logs from this device? Storage folder choices will be kept.',
    confirmLabel: 'Reset',
    confirmVariant: TechButtonVariant.danger,
  );

  if (!confirmed) {
    return;
  }

  await controller.resetOfflineData();
}

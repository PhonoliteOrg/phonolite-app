import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/settings/dialogs/managed_offline_storage_paths.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button_variant.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';

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

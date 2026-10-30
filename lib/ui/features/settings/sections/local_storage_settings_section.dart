import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/ui/features/settings/dialogs/settings_dialogs.dart';
import 'package:phonolite_app/ui/features/settings/widgets/download_quality_setting.dart';
import 'package:phonolite_app/ui/features/settings/widgets/offline_storage_section.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';

class LocalStorageSettingsSection extends BaseSection {
  final AppController controller;
  final DownloadSettingsController? downloadSettings;
  final VoidCallback? onDownloadQuality;

  const LocalStorageSettingsSection({
    super.key,
    required this.controller,
    this.downloadSettings,
    this.onDownloadQuality,
  });

  @override
  String get sectionTitle => 'Local Storage';

  @override
  List<Widget> sectionContent(BuildContext context) => [
    if (onDownloadQuality != null) ...[
      DownloadQualitySetting(
        controller: downloadSettings ?? DownloadSettingsController.instance,
        onOpen: onDownloadQuality!,
      ),
      const SettingsDivider(),
    ],
    StreamBuilder<OfflineStorageLocations>(
      stream: controller.offlineStorageLocationsStream,
      initialData: controller.offlineStorageLocations,
      builder: (context, snapshot) {
        final locations = snapshot.data ?? controller.offlineStorageLocations;
        final logger = SettingsController.instance;

        return StreamBuilder<LogStorageLocation>(
          stream: logger.storageLocationStream,
          initialData: logger.storageLocation,
          builder: (context, logSnapshot) {
            final logsLocation = logSnapshot.data ?? logger.storageLocation;

            return OfflineStorageSection(
              locations: locations,
              logsLocation: logsLocation,
              onChangeMetadata: locations == null
                  ? null
                  : () => settingsOpenStoragePathDialog(
                      context,
                      title: 'Metadata database folder',
                      initialPath: locations.metadataDirectory,
                      isDefault: locations.metadataDirectoryIsDefault,
                      onSave: controller.updateOfflineMetadataDirectory,
                    ),
              onResetMetadata: locations == null ? null : () => controller.resetOfflineMetadataDirectory(),
              onOpenMetadata: locations == null
                  ? null
                  : () => settingsOpenStorageDirectory(context, locations.metadataDirectory),
              onChangeDownloads: locations == null
                  ? null
                  : () => settingsOpenStoragePathDialog(
                      context,
                      title: 'Downloaded audio folder',
                      initialPath: locations.downloadsDirectory,
                      isDefault: locations.downloadsDirectoryIsDefault,
                      onSave: controller.updateOfflineDownloadsDirectory,
                    ),
              onResetDownloads: locations == null ? null : () => controller.resetOfflineDownloadsDirectory(),
              onOpenDownloads: locations == null
                  ? null
                  : () => settingsOpenStorageDirectory(context, locations.downloadsDirectory),
              onChangeLogs: logsLocation == null
                  ? null
                  : () => settingsOpenStoragePathDialog(
                      context,
                      title: 'Logs storage folder',
                      initialPath: logsLocation.directory,
                      isDefault: logsLocation.isDefault,
                      onSave: logger.updateStorageDirectory,
                    ),
              onResetLogs: logsLocation == null ? null : () => settingsResetLogsStorage(context),
              onOpenLogs: logsLocation == null
                  ? null
                  : () => settingsOpenStorageDirectory(context, logsLocation.directory),
              onResetOfflineData: locations == null ? null : () => settingsConfirmResetOfflineData(context, controller),
            );
          },
        );
      },
    ),
  ];
}

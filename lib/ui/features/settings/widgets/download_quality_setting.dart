import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/download_settings_controller.dart';
import 'package:phonolite_app/ui/features/settings/widgets/download_quality_selection.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

class DownloadQualitySetting extends StatelessWidget {
  final DownloadSettingsController controller;
  final VoidCallback onOpen;

  const DownloadQualitySetting({super.key, required this.controller, required this.onOpen});

  String get _subtitle {
    if (controller.ready) {
      final quality = controller.settings.quality;

      return '${quality.label} · ${DownloadQualitySelection.description(quality)}';
    }

    if (controller.error != null) return 'Download settings unavailable';

    return 'Choose the size of future downloads';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => KeyedSubtree(
      key: const ValueKey('download-quality-setting'),
      child: buildSettingsRow(
        context,
        leading: const Icon(PhonoliteIcons.download),
        title: 'Download quality',
        subtitle: _subtitle,
        trailing: const Icon(PhonoliteIcons.chevronRight),
        onTap: onOpen,
      ),
    ),
  );
}

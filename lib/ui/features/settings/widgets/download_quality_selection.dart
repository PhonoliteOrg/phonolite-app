import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_radio_row.dart';

/// Presentation of the five supported profiles; persistence stays in the controller.
class DownloadQualitySelection extends StatelessWidget {
  final DownloadQuality quality;
  final bool enabled;
  final ValueChanged<DownloadQuality> onSelected;

  const DownloadQualitySelection({super.key, required this.quality, required this.onSelected, this.enabled = true});

  static String description(DownloadQuality quality) {
    if (quality.isOriginal) return 'Source file unchanged · Size varies';

    return '${quality.bitrateKbps} kbps · ~${quality.megabytesPerHour!.round()} MB/hour';
  }

  @override
  Widget build(BuildContext context) => RadioGroup<DownloadQuality>(
    groupValue: quality,
    onChanged: (value) {
      if (enabled && value != null) onSelected(value);
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in DownloadQuality.values) ...[
          if (option != DownloadQuality.values.first) const SettingsDivider(),
          ObsidianRadioRow<DownloadQuality>(
            key: ValueKey('download-quality-${option.wireValue}'),
            value: option,
            title: option == DownloadQuality.high ? '${option.label} · Recommended' : option.label,
            subtitle: description(option),
            selected: quality == option,
            enabled: enabled,
            onSelected: onSelected,
          ),
        ],
      ],
    ),
  );
}

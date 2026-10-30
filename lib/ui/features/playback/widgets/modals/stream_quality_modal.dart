import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/playback_modal_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

Future<void> playbackShowStreamModal(
  BuildContext context, {
  required StreamMode current,
  required ValueChanged<StreamMode> onSelected,
}) async {
  final result = await showDialog<StreamMode>(
    context: context,
    builder: (dialogContext) {
      final items = const [
        (mode: StreamMode.original, label: 'Original (source-preserving · QUIC)'),
        (mode: StreamMode.high, label: 'High quality (160 kbps)'),
        (mode: StreamMode.medium, label: 'Medium quality (96 kbps)'),
        (mode: StreamMode.low, label: 'Low quality (48 kbps)'),
      ];

      return ObsidianAlertDialog(
        title: const Text('Stream Quality'),
        actions: [ModalActionButton(label: 'Close', onPressed: () => Navigator.of(dialogContext).pop())],
        content: SizedBox(
          width: playbackScaled(dialogContext, 320),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: playbackScaled(dialogContext, 4)),
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                Divider(height: playbackScaled(context, 1), color: ObsidianPalette.textMuted.withByteOpacity(0.25)),
            itemBuilder: (context, index) {
              final (:mode, :label) = items[index];
              final isSelected = mode == current;

              return PlaybackHudModalListRow(
                title: label,
                trailing: isSelected
                    ? const Icon(PhonoliteIcons.check, color: ObsidianPalette.gold)
                    : const SizedBox.shrink(),
                enabled: true,
                isSelected: isSelected,
                onTap: () => Navigator.of(dialogContext).pop(mode),
              );
            },
          ),
        ),
      );
    },
  );

  if (result != null && result != current) {
    onSelected(result);
  }
}

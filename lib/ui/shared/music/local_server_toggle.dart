import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_toggle_option.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/server_icon.dart';

class LocalServerToggle extends StatelessWidget {
  final ActionScope value;
  final ValueChanged<ActionScope> onChanged;

  const LocalServerToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        _LocalServerOption(
          label: 'LOCAL',
          icon: const Icon(PhonoliteIcons.download),
          selected: value == ActionScope.local,
          onTap: () => onChanged(ActionScope.local),
        ),
        _LocalServerOption(
          label: 'SERVER',
          icon: const ServerIcon(),
          selected: value == ActionScope.server,
          onTap: () => onChanged(ActionScope.server),
        ),
      ],
    );
  }
}

class _LocalServerOption extends ObsidianToggleOption {
  const _LocalServerOption({
    required super.label,
    required super.icon,
    required bool selected,
    required VoidCallback onTap,
  }) : super(
         isActive: selected,
         onPressed: onTap,
         touchMinimumSize: const Size(112, 48),
         touchFontSize: null,
         visualDensity: VisualDensity.standard,
       );
}

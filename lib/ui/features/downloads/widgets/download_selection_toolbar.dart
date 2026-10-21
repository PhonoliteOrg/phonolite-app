import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class DownloadSelectionToolbar extends StatelessWidget {
  static const double _compactWidth = 640;

  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback? onRemove;

  const DownloadSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < _compactWidth;
    final allSelected = totalCount > 0 && selectedCount == totalCount;
    final toggleLabel = allSelected ? 'Deselect all' : 'Select all';
    final toggleEnabled = totalCount > 0;
    final VoidCallback? toggleAction;

    if (!toggleEnabled) {
      toggleAction = null;
    } else {
      toggleAction = allSelected ? onDeselectAll : onSelectAll;
    }

    final buttonTextStyle = GoogleFonts.rajdhani(
      fontSize: isCompact ? 12 : 14,
      fontWeight: FontWeight.w700,
      letterSpacing: isCompact ? 0.8 : 1.2,
    );

    final actions = <Widget>[
      Tooltip(
        message: toggleLabel,
        child: _HudTextButton(
          label: toggleLabel,
          isActive: allSelected,
          onPressed: toggleAction,
          textStyle: buttonTextStyle,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: isCompact ? 4 : 6),
        ),
      ),
      Tooltip(
        message: 'Remove selected',
        child: ObsidianHudIconButton(
          icon: PhonoliteIcons.trash2,
          size: isCompact ? 22 : 26,
          onPressed: selectedCount > 0 ? onRemove : null,
        ),
      ),
      Tooltip(
        message: 'Cancel',
        child: ObsidianHudIconButton(icon: PhonoliteIcons.x, size: isCompact ? 22 : 26, onPressed: onCancel),
      ),
    ];

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: isCompact ? 4 : 10,
      runSpacing: isCompact ? 4 : 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
  }
}

class _HudTextButton extends StatelessWidget {
  static const Duration _transition = Duration(milliseconds: 200);

  final String label;
  final bool isActive;
  final VoidCallback? onPressed;
  final TextStyle? textStyle;
  final EdgeInsets padding;

  const _HudTextButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
    required this.textStyle,
    required this.padding,
  });

  Color _colorFor(Set<WidgetState> states) {
    final enabled = !states.contains(WidgetState.disabled);

    if (!enabled) {
      return ObsidianPalette.textMuted.withValues(alpha: 0.6);
    }

    final highlight = isActive || states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed);

    return highlight ? ObsidianPalette.gold : ObsidianPalette.textMuted;
  }

  double _glowFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return 0.0;
    }

    if (states.contains(WidgetState.hovered)) {
      return 0.7;
    }

    return isActive || states.contains(WidgetState.pressed) ? 0.35 : 0.0;
  }

  TextStyle? _textStyleFor(Set<WidgetState> states) {
    final glowOpacity = _glowFor(states);

    return textStyle?.copyWith(
      fontWeight: FontWeight.w700,
      shadows: [
        if (glowOpacity > 0) Shadow(color: ObsidianPalette.gold.withValues(alpha: glowOpacity), blurRadius: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: withButtonHaptic(onPressed),
      style: ButtonStyle(
        animationDuration: _transition,
        foregroundColor: WidgetStateProperty.resolveWith(_colorFor),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(padding),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStateProperty.resolveWith(_textStyleFor),
        mouseCursor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? SystemMouseCursors.basic : SystemMouseCursors.click,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }
}

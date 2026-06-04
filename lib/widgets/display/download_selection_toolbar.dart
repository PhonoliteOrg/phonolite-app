import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ui/obsidian_widgets.dart';
import '../ui/obsidian_theme.dart';

class DownloadSelectionToolbar extends StatelessWidget {
  const DownloadSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onRemove,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final allSelected = totalCount > 0 && selectedCount == totalCount;
    final toggleLabel = allSelected ? 'Deselect all' : 'Select all';
    final toggleEnabled = totalCount > 0;
    final buttonTextStyle = GoogleFonts.rajdhani(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    final actions = <Widget>[
      Tooltip(
        message: toggleLabel,
        child: _HudTextButton(
          label: toggleLabel,
          isActive: allSelected,
          onPressed: !toggleEnabled
              ? null
              : allSelected
              ? onDeselectAll
              : onSelectAll,
          textStyle: buttonTextStyle,
        ),
      ),
      Tooltip(
        message: 'Remove selected',
        child: ObsidianHudIconButton(
          icon: Icons.delete_outline_rounded,
          onPressed: selectedCount > 0 ? onRemove : null,
        ),
      ),
      Tooltip(
        message: 'Cancel',
        child: ObsidianHudIconButton(
          icon: Icons.close_rounded,
          onPressed: onCancel,
        ),
      ),
    ];

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
  }
}

class _HudTextButton extends StatelessWidget {
  const _HudTextButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
    required this.textStyle,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onPressed;
  final TextStyle? textStyle;

  static const _transition = Duration(milliseconds: 200);

  Color _colorFor(Set<WidgetState> states) {
    final enabled = !states.contains(WidgetState.disabled);
    if (!enabled) {
      return ObsidianPalette.textMuted.withValues(alpha: 0.6);
    }
    final highlight =
        isActive ||
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    return highlight ? ObsidianPalette.gold : ObsidianPalette.textMuted;
  }

  double _glowFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return 0.0;
    }
    return states.contains(WidgetState.hovered)
        ? 0.7
        : (isActive || states.contains(WidgetState.pressed) ? 0.35 : 0.0);
  }

  TextStyle? _textStyleFor(Set<WidgetState> states) {
    final glowOpacity = _glowFor(states);
    return textStyle?.copyWith(
      fontWeight: FontWeight.w700,
      shadows: [
        if (glowOpacity > 0)
          Shadow(
            color: ObsidianPalette.gold.withValues(alpha: glowOpacity),
            blurRadius: 10,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        animationDuration: _transition,
        foregroundColor: WidgetStateProperty.resolveWith(_colorFor),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStateProperty.resolveWith(_textStyleFor),
        mouseCursor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }
}

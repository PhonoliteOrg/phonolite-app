import 'package:flutter/material.dart';

import 'phonolite_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'obsidian_theme.dart';
import 'obsidian_widgets.dart';
import 'tech_button.dart';
import '../modals/modal_action_button.dart';
import '../modals/obsidian_dialog.dart';
import '../modals/obsidian_modal_scope.dart';
import 'button_haptics.dart';
import 'hover_row.dart';

class ObsidianMenuAction {
  const ObsidianMenuAction({
    required this.label,
    this.icon,
    this.iconWidget,
    required this.onTap,
    this.variant = TechButtonVariant.standard,
    this.isActive = false,
  }) : assert((icon == null) != (iconWidget == null));

  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final TechButtonVariant variant;
  final bool isActive;
}

class ObsidianOverflowActionButton extends StatelessWidget {
  const ObsidianOverflowActionButton({
    super.key,
    required this.actions,
    required this.tooltip,
    this.icon = PhonoliteIcons.ellipsisVertical,
    this.size = 22,
    this.modalTitle,
    this.resolveActions,
  }) : assert(resolveActions == null || modalTitle != null);

  final List<ObsidianMenuAction> actions;
  final String tooltip;
  final IconData icon;
  final double size;

  /// Opens the actions in a standard app modal when provided.
  final String? modalTitle;
  final Future<List<ObsidianMenuAction>> Function()? resolveActions;

  @override
  Widget build(BuildContext context) {
    final compact = ObsidianModalScope.isCompact(context);
    final enabled =
        resolveActions != null || actions.any((action) => action.onTap != null);
    if (!enabled) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: false,
          label: tooltip,
          child: ObsidianHudIconButton(icon: icon, size: size),
        ),
      );
    }

    if (modalTitle != null) {
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: ObsidianPalette.textMuted, size: size),
        onPressed: withButtonHaptic(() => _showModal(context)),
      );
    }

    return Semantics(
      button: true,
      label: tooltip,
      child: PopupMenuButton<int>(
        onOpened: withButtonHaptic(() {}),
        tooltip: tooltip,
        color: ObsidianPalette.obsidianElevated,
        elevation: 8,
        popUpAnimationStyle: AnimationStyle.noAnimation,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ObsidianPalette.border),
          borderRadius: BorderRadius.circular(4),
        ),
        position: PopupMenuPosition.under,
        onSelected: withSelectionHaptic(
          (index) => actions[index].onTap?.call(),
        ),
        itemBuilder: (context) => [
          for (final entry in actions.indexed)
            _menuItem(index: entry.$1, action: entry.$2, compact: compact),
        ],
        icon: Icon(icon, color: ObsidianPalette.textMuted, size: size),
      ),
    );
  }

  Future<void> _showModal(BuildContext context) async {
    Future<List<ObsidianMenuAction>>? pendingActions;
    final selected = await showDialog<ObsidianMenuAction>(
      context: context,
      builder: (dialogContext) => ObsidianModalScope(
        builder: (context) {
          final compact = ObsidianModalScope.usesTouchTargets(context);
          return ObsidianAlertDialog(
            title: Text(modalTitle!),
            scrollable: true,
            content: SizedBox(
              width: 360,
              child: resolveActions == null
                  ? _modalActions(dialogContext, actions, compact: compact)
                  : FutureBuilder<List<ObsidianMenuAction>>(
                      future: pendingActions ??= resolveActions!(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text('Unable to load track actions.');
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return _modalActions(
                          dialogContext,
                          snapshot.data!,
                          compact: compact,
                        );
                      },
                    ),
            ),
            actions: [
              ModalActionButton(
                label: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      ),
    );
    if (context.mounted) {
      selected?.onTap?.call();
    }
  }

  Widget _modalActions(
    BuildContext context,
    List<ObsidianMenuAction> actions, {
    required bool compact,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in actions)
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 56 : 48),
          child: ObsidianHoverRow(
            enabled: action.onTap != null,
            borderColor: action.variant == TechButtonVariant.danger
                ? Colors.redAccent
                : ObsidianPalette.gold,
            onTap: action.onTap == null
                ? null
                : () => Navigator.of(context).pop(action),
            child: _actionContent(action, compact: compact, muted: true),
          ),
        ),
    ],
  );

  PopupMenuItem<int> _menuItem({
    required int index,
    required ObsidianMenuAction action,
    required bool compact,
  }) => PopupMenuItem<int>(
    value: index,
    enabled: action.onTap != null,
    height: compact ? 56 : 40,
    child: _actionContent(action, compact: compact),
  );

  Widget _actionContent(
    ObsidianMenuAction action, {
    required bool compact,
    bool muted = false,
  }) {
    final enabled = action.onTap != null;
    final danger = action.variant == TechButtonVariant.danger;
    final baseColor = danger
        ? Colors.redAccent
        : muted
        ? ObsidianPalette.textMuted
        : ObsidianPalette.textPrimary;
    final color = enabled
        ? baseColor
        : ObsidianPalette.textMuted.withValues(alpha: 0.55);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(
            size: compact ? 22 : 18,
            color: enabled && action.isActive ? ObsidianPalette.gold : color,
            shadows: enabled && action.isActive
                ? [
                    Shadow(
                      color: ObsidianPalette.gold.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : const [],
          ),
          child: action.iconWidget ?? Icon(action.icon),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            action.label,
            style: GoogleFonts.rajdhani(
              fontSize: compact ? 16 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

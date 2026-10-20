import 'package:flutter/material.dart';

import '../ui/obsidian_glass_surface.dart';
import 'obsidian_modal_scope.dart';

abstract final class ObsidianModalStyle {
  static const insetPadding = EdgeInsets.all(24);
  static const titlePadding = EdgeInsets.fromLTRB(24, 20, 24, 0);
  static const contentPadding = EdgeInsets.fromLTRB(24, 16, 24, 0);
  static const actionsPadding = EdgeInsets.fromLTRB(24, 12, 24, 16);
  static const actionSpacing = 8.0;

  static TextStyle? titleStyle(BuildContext context) =>
      DialogTheme.of(context).titleTextStyle ??
      Theme.of(context).textTheme.titleLarge;

  static TextStyle? bodyStyle(BuildContext context) =>
      DialogTheme.of(context).contentTextStyle ??
      Theme.of(context).textTheme.bodyMedium;
}

/// Keeps dismiss actions before the primary action and wraps on narrow screens.
class ObsidianModalActions extends StatelessWidget {
  const ObsidianModalActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: ObsidianModalStyle.actionSpacing,
      overflowSpacing: ObsidianModalStyle.actionSpacing,
      children: children,
    );
  }
}

class ObsidianDialog extends Dialog {
  const ObsidianDialog({
    super.key,
    super.child,
    super.insetPadding = ObsidianModalStyle.insetPadding,
    super.insetAnimationDuration,
    super.insetAnimationCurve,
    super.shape,
    super.alignment,
    super.constraints,
    super.semanticsRole,
  }) : super(
         backgroundColor: Colors.transparent,
         surfaceTintColor: Colors.transparent,
         elevation: 0,
       );

  @override
  Widget build(BuildContext context) =>
      ObsidianModalScope(builder: _buildDialog);

  Widget _buildDialog(BuildContext context) {
    final effectiveInset = insetPadding == ObsidianModalStyle.insetPadding
        ? ObsidianModalScope.insetsOf(context)
        : insetPadding ?? ObsidianModalStyle.insetPadding;
    final effectiveShape =
        shape ??
        DialogTheme.of(context).shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            Theme.of(context).useMaterial3 ? 28 : 4,
          ),
        );
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: effectiveInset,
      insetAnimationDuration: insetAnimationDuration,
      insetAnimationCurve: insetAnimationCurve,
      shape: effectiveShape,
      alignment: alignment,
      constraints:
          constraints ??
          (ObsidianModalScope.isCompact(context)
              ? BoxConstraints(
                  minWidth:
                      MediaQuery.sizeOf(context).width -
                      effectiveInset.horizontal -
                      MediaQuery.paddingOf(context).horizontal,
                )
              : null),
      semanticsRole: semanticsRole,
      child: ObsidianGlassSurface(
        shape: effectiveShape,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Retains Flutter's alert layout, text scaling, and accessibility semantics.
class ObsidianAlertDialog extends AlertDialog {
  const ObsidianAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.iconColor,
    super.title,
    super.titlePadding = ObsidianModalStyle.titlePadding,
    super.titleTextStyle,
    super.content,
    super.contentPadding = ObsidianModalStyle.contentPadding,
    super.contentTextStyle,
    super.actions,
    super.actionsPadding = ObsidianModalStyle.actionsPadding,
    super.actionsAlignment = MainAxisAlignment.end,
    super.actionsOverflowAlignment = OverflowBarAlignment.end,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing = ObsidianModalStyle.actionSpacing,
    super.buttonPadding = const EdgeInsets.symmetric(horizontal: 8),
    super.semanticLabel,
    super.insetPadding = ObsidianModalStyle.insetPadding,
    super.shape,
    super.alignment,
    super.constraints,
    super.scrollable,
  });

  @override
  Widget build(BuildContext context) =>
      ObsidianModalScope(builder: _buildAlert);

  Widget _buildAlert(BuildContext context) {
    final dialog = super.build(context) as Dialog;
    return ObsidianDialog(
      insetPadding: dialog.insetPadding,
      shape: dialog.shape,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: dialog.child,
    );
  }
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_style.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';

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
  }) : super(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0);

  Widget _buildDialog(BuildContext context) {
    final effectiveInset = insetPadding == ObsidianModalStyle.insetPadding
        ? ObsidianModalScope.insetsOf(context)
        : insetPadding ?? ObsidianModalStyle.insetPadding;
    final effectiveShape =
        shape ??
        DialogTheme.of(context).shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(Theme.of(context).useMaterial3 ? 28 : 4));

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
      child: ObsidianGlassSurface(shape: effectiveShape, child: child ?? const SizedBox.shrink()),
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildDialog);
}

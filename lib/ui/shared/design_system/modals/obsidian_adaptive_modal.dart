import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_style.dart';

typedef ObsidianAdaptiveModalBuilder = Widget Function(
  BuildContext context,
  ObsidianAdaptiveModalPresentation presentation,
);

enum ObsidianAdaptiveModalPresentation { sheet, dialog }

class ObsidianAdaptiveModal {
  static const double compactBreakpoint = ObsidianModalScope.compactBreakpoint;
  static const double compactHeightFactor = 0.92;
  static const Size maxDialogSize = Size(680, 720);

  const ObsidianAdaptiveModal._();

  static Future<T?> show<T>({
    required BuildContext context,
    required ObsidianAdaptiveModalBuilder builder,
    bool barrierDismissible = true,
    bool useCompactSheet = true,
  }) {
    final size = MediaQuery.sizeOf(context);

    if (useCompactSheet && size.width < compactBreakpoint) {
      return showModalBottomSheet<T>(
        context: context,
        // Match showDialog's default so both presentations sit above the shell.
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: barrierDismissible,
        useSafeArea: true,
        barrierColor: ObsidianModalStyle.sheetBarrierColor,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final size = MediaQuery.sizeOf(sheetContext);

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
            child: SizedBox(
              height: (size.height - MediaQuery.viewInsetsOf(sheetContext).bottom) * compactHeightFactor,
              child: ObsidianModalScope(
                builder: (context) => builder(context, ObsidianAdaptiveModalPresentation.sheet),
              ),
            ),
          );
        },
      );
    }

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: ObsidianModalStyle.sheetBarrierColor,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final inset = ObsidianModalScope.insetsOf(dialogContext);
        final dialogWidth = (size.width - inset.horizontal).clamp(0.0, maxDialogSize.width).toDouble();
        final dialogHeight = (size.height - inset.vertical).clamp(0.0, maxDialogSize.height).toDouble();

        return Dialog(
          insetPadding: inset,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: builder(dialogContext, ObsidianAdaptiveModalPresentation.dialog),
          ),
        );
      },
    );
  }
}

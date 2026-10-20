import 'package:flutter/material.dart';

import '../ui/obsidian_glass_surface.dart';
import '../ui/obsidian_theme.dart';
import 'modal_action_button.dart';
import 'obsidian_dialog.dart';
import 'obsidian_modal_scope.dart';

enum ObsidianAdaptiveModalPresentation { sheet, dialog }

typedef ObsidianAdaptiveModalBuilder =
    Widget Function(
      BuildContext context,
      ObsidianAdaptiveModalPresentation presentation,
    );

class ObsidianAdaptiveModal {
  const ObsidianAdaptiveModal._();

  static const compactBreakpoint = ObsidianModalScope.compactBreakpoint;
  static const compactHeightFactor = 0.92;
  static const dialogInset = ObsidianModalStyle.insetPadding;
  static const maxDialogSize = Size(680, 720);

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
        isScrollControlled: true,
        isDismissible: barrierDismissible,
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final size = MediaQuery.sizeOf(sheetContext);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SizedBox(
              height:
                  (size.height - MediaQuery.viewInsetsOf(sheetContext).bottom) *
                  compactHeightFactor,
              child: ObsidianModalScope(
                builder: (context) =>
                    builder(context, ObsidianAdaptiveModalPresentation.sheet),
              ),
            ),
          );
        },
      );
    }

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final inset = ObsidianModalScope.insetsOf(dialogContext);
        final dialogWidth = (size.width - inset.horizontal)
            .clamp(0.0, maxDialogSize.width)
            .toDouble();
        final dialogHeight = (size.height - inset.vertical)
            .clamp(0.0, maxDialogSize.height)
            .toDouble();
        return Dialog(
          insetPadding: inset,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: builder(
              dialogContext,
              ObsidianAdaptiveModalPresentation.dialog,
            ),
          ),
        );
      },
    );
  }
}

class ObsidianModalSurface extends StatelessWidget {
  const ObsidianModalSurface({
    super.key,
    required this.title,
    required this.child,
    this.headerActions,
    this.showDragHandle = false,
  });

  final String title;
  final Widget child;
  final Widget? headerActions;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) =>
      ObsidianModalScope(builder: _buildSurface);

  Widget _buildSurface(BuildContext context) {
    final heading = Text(
      title,
      textAlign: TextAlign.left,
      maxLines: headerActions == null ? null : 2,
      overflow: headerActions == null ? null : TextOverflow.ellipsis,
      style: ObsidianModalStyle.titleStyle(context),
    );
    return ObsidianGlassSurface(
      child: SafeArea(
        top: !showDragHandle,
        child: Column(
          children: [
            if (showDragHandle) const _ObsidianModalDragHandle(),
            Padding(
              padding: ObsidianModalStyle.titlePadding,
              child: headerActions == null
                  ? Align(alignment: Alignment.centerLeft, child: heading)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: heading),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: headerActions!,
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: Padding(
                padding: ObsidianModalStyle.contentPadding,
                child: DefaultTextStyle.merge(
                  style: ObsidianModalStyle.bodyStyle(context),
                  child: child,
                ),
              ),
            ),
            Padding(
              padding: ObsidianModalStyle.actionsPadding,
              child: ObsidianModalActions(
                children: [
                  ModalActionButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObsidianModalDragHandle extends StatelessWidget {
  const _ObsidianModalDragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ObsidianPalette.textMuted.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: 42, height: 4),
        ),
      ),
    );
  }
}

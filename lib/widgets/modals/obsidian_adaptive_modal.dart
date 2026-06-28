import 'package:flutter/material.dart';

import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

enum ObsidianAdaptiveModalPresentation { sheet, dialog }

typedef ObsidianAdaptiveModalBuilder =
    Widget Function(
      BuildContext context,
      ObsidianAdaptiveModalPresentation presentation,
    );

class ObsidianAdaptiveModal {
  const ObsidianAdaptiveModal._();

  static const compactBreakpoint = 820.0;
  static const compactHeightFactor = 0.92;
  static const dialogInset = EdgeInsets.symmetric(horizontal: 24, vertical: 24);
  static const maxDialogSize = Size(680, 720);

  static Future<T?> show<T>({
    required BuildContext context,
    required ObsidianAdaptiveModalBuilder builder,
    bool barrierDismissible = true,
  }) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < compactBreakpoint) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        isDismissible: barrierDismissible,
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final size = MediaQuery.sizeOf(sheetContext);
          return SizedBox(
            height: size.height * compactHeightFactor,
            child: builder(
              sheetContext,
              ObsidianAdaptiveModalPresentation.sheet,
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
        final dialogWidth = (size.width - dialogInset.horizontal)
            .clamp(0.0, maxDialogSize.width)
            .toDouble();
        final dialogHeight = (size.height - dialogInset.vertical)
            .clamp(0.0, maxDialogSize.height)
            .toDouble();
        return Dialog(
          insetPadding: dialogInset,
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
    this.blur = 20,
    this.cut = 18,
  });

  final String title;
  final Widget child;
  final Widget? headerActions;
  final bool showDragHandle;
  final double blur;
  final double cut;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = showDragHandle ? 18.0 : 20.0;
    return GlassPanel(
      cut: cut,
      blur: blur,
      padding: EdgeInsets.zero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          ObsidianPalette.obsidianElevated.withValues(alpha: 0.98),
          ObsidianPalette.obsidian.withValues(alpha: 0.96),
        ],
      ),
      child: SafeArea(
        top: !showDragHandle,
        child: Column(
          children: [
            if (showDragHandle) const _ObsidianModalDragHandle(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                showDragHandle ? 4 : 14,
                12,
                headerActions == null ? 12 : 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (headerActions != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  12,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: headerActions,
                ),
              ),
            const Divider(height: 1),
            Expanded(child: child),
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

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';
import 'package:phonolite_app/ui/shell/navigation/app_side_navigation.dart';

/// Keeps the window buttons above root dialogs. The content SafeArea consumes
/// the caption inset, while the side navigation paints up to the window edge.
class WindowsWindowFrame extends StatefulWidget {
  final Widget child;

  const WindowsWindowFrame({super.key, required this.child});

  @override
  State<WindowsWindowFrame> createState() => _WindowsWindowFrameState();
}

class _WindowsWindowFrameState extends State<WindowsWindowFrame> with WindowListener {
  late Future<bool> _maximized;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _maximized = windowManager.isMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    setState(() {
      _maximized = Future.value(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final content = MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: kWindowCaptionHeight),
        viewPadding: media.viewPadding.copyWith(top: kWindowCaptionHeight),
      ),
      child: widget.child,
    );

    return FutureBuilder<bool>(
      future: _maximized,
      builder: (context, snapshot) {
        final maximized = snapshot.data ?? false;

        // The hidden Windows frame retains its side and bottom resize borders.
        return DragToResizeArea(
          resizeEdgeSize: 4,
          enableResizeEdges: maximized ? const [] : const [ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.topRight],
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Positioned(
                top: 0,
                left: usesSideNavigation(context) ? AppSideNavigation.widthFor(context) : 0,
                right: 0,
                height: kWindowCaptionHeight,
                child: Row(
                  children: [
                    const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
                    _CaptionButton(label: 'Minimize', icon: Icons.remove, onPressed: windowManager.minimize),
                    _CaptionButton(
                      label: maximized ? 'Restore' : 'Maximize',
                      icon: maximized ? PhonoliteIcons.copy : PhonoliteIcons.square,
                      onPressed: maximized ? windowManager.unmaximize : () => windowManager.maximize(),
                    ),
                    // close() posts SC_CLOSE so the desktop lifecycle can apply the tray preference.
                    _CaptionButton(label: 'Close', icon: PhonoliteIcons.x, close: true, onPressed: windowManager.close),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool close;

  const _CaptionButton({required this.label, required this.icon, required this.onPressed, this.close = false});

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> with PointerInteraction<_CaptionButton> {
  @override
  bool get interactionEnabled => true;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.close ? const Color(0xffc42b1c) : Colors.white12;

    return pointerRegion(
      onTap: widget.onPressed,
      semanticLabel: widget.label,
      child: Container(
        width: 46,
        height: kWindowCaptionHeight,
        color: hovered || pressed ? highlight : Colors.transparent,
        alignment: Alignment.center,
        child: Icon(widget.icon, size: 14, color: ObsidianPalette.textPrimary),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Maps desktop mouse side buttons to the active menu's navigation actions.
class DesktopMouseNavigation extends StatelessWidget {
  const DesktopMouseNavigation({
    super.key,
    required this.onBack,
    required this.onForward,
    required this.child,
  });

  final VoidCallback onBack;
  final VoidCallback onForward;
  final Widget child;

  bool get _enabled =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }
    switch (event.buttons) {
      case kBackMouseButton:
        onBack();
      case kForwardMouseButton:
        onForward();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _enabled ? _handlePointerDown : null,
    child: child,
  );
}

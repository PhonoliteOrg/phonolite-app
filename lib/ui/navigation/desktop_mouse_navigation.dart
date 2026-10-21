import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:phonolite_app/ui/navigation/desktop_input_policy.dart';

/// Maps desktop mouse side buttons to the active menu's navigation actions.
class DesktopMouseNavigation extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onForward;
  final Widget child;

  const DesktopMouseNavigation({super.key, required this.onBack, required this.onForward, required this.child});

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
    onPointerDown: desktopInputEnabled ? _handlePointerDown : null,
    child: child,
  );
}

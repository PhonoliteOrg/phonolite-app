import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:phonolite_app/ui/navigation/desktop_input_policy.dart';

/// Toggles playback with Space without taking keys from editors or controls.
/// Place above the app's Navigator so the shortcut survives tab focus changes.
class DesktopPlaybackShortcuts extends StatelessWidget {
  static const SingleActivator _space = SingleActivator(LogicalKeyboardKey.space);

  final VoidCallback onTogglePlayPause;
  final Widget child;

  const DesktopPlaybackShortcuts({super.key, required this.onTogglePlayPause, required this.child});

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.synthesized || !_space.accepts(event, HardwareKeyboard.instance)) {
      return KeyEventResult.ignored;
    }

    final context = FocusManager.instance.primaryFocus?.context;

    if (context != null) {
      if (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null ||
          ModalRoute.of(context) is PopupRoute<dynamic>) {
        return KeyEventResult.ignored;
      }
    }

    // Also stop repeats from reactivating a focused play/pause button.
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    if (context != null) {
      final activate = Actions.maybeFind<ActivateIntent>(context);

      if (activate?.isEnabled(const ActivateIntent()) ?? false) {
        return KeyEventResult.ignored;
      }
    }

    if (event is KeyDownEvent) {
      onTogglePlayPause();
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!desktopInputEnabled) {
      return child;
    }

    return Focus(autofocus: true, skipTraversal: true, onKeyEvent: _handleKeyEvent, child: child);
  }
}

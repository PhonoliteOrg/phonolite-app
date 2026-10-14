import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Toggles playback with Space without taking keys from editors or controls.
/// Place above the app's Navigator so the shortcut survives tab focus changes.
class DesktopPlaybackShortcuts extends StatelessWidget {
  const DesktopPlaybackShortcuts({
    super.key,
    required this.onTogglePlayPause,
    required this.child,
  });

  final VoidCallback onTogglePlayPause;
  final Widget child;

  static const _space = SingleActivator(LogicalKeyboardKey.space);

  bool get _enabled =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.synthesized ||
        !_space.accepts(event, HardwareKeyboard.instance)) {
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
    if (!_enabled) {
      return child;
    }
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }
}

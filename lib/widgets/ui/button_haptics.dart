import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get _usesButtonHaptics =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<void> _lightTap() async {
  try {
    await HapticFeedback.lightImpact();
  } on PlatformException {
    // Feedback is optional; an unavailable actuator must not block the action.
  } on MissingPluginException {
    // Embedded hosts without platform haptics still handle button actions.
  }
}

/// Adds feedback at the control that handles the press, preserving disabled state.
VoidCallback? withButtonHaptic(VoidCallback? action) {
  if (action == null || !_usesButtonHaptics) return action;
  return () {
    unawaited(_lightTap());
    action();
  };
}

/// The equivalent for controls that select a value, such as checkboxes and menus.
ValueChanged<T>? withSelectionHaptic<T>(ValueChanged<T>? action) {
  if (action == null || !_usesButtonHaptics) return action;
  return (value) {
    unawaited(_lightTap());
    action(value);
  };
}

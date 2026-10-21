import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';

/// Shared pointer lifecycle for controls that paint their own interaction.
/// Each control keeps its visual design; enabling, cancellation and stale
/// hover/press cleanup have one implementation.
mixin PointerInteraction<T extends StatefulWidget> on State<T> {
  bool _hovered = false;
  bool _pressed = false;

  bool get interactionEnabled;

  bool get hovered => _hovered;

  bool get pressed => _pressed;

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!interactionEnabled) {
      _hovered = false;
      _pressed = false;
    }
  }

  Widget pointerRegion({required Widget child, required VoidCallback? onTap, HitTestBehavior? behavior}) => MouseRegion(
    onEnter: interactionEnabled ? (_) => _hover(true) : null,
    onExit: interactionEnabled ? (_) => _hover(false) : null,
    cursor: interactionEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      onTap: withButtonHaptic(interactionEnabled ? onTap : null),
      onTapDown: interactionEnabled ? (_) => _press(true) : null,
      onTapUp: interactionEnabled ? (_) => _press(false) : null,
      onTapCancel: interactionEnabled ? () => _press(false) : null,
      behavior: behavior,
      child: child,
    ),
  );

  void _hover(bool value) {
    if (_hovered != value) {
      setState(() => _hovered = value);
    }
  }

  void _press(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }
}

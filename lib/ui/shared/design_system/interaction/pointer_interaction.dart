import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';

/// Shared pointer and keyboard lifecycle for controls that paint their own interaction.
/// Each control keeps its visual design; enabling, cancellation and stale
/// hover/press cleanup have one implementation.
///
/// [pointerRegion] makes the control a real button: it joins focus traversal, activates with
/// Enter/Space through [ActivateIntent], and is announced as a button. A keyboard focus highlight
/// reports through [hovered], so each control's hover styling doubles as its focus indicator.
mixin PointerInteraction<T extends StatefulWidget> on State<T> {
  bool _hovered = false;
  bool _focusHighlighted = false;
  bool _pressed = false;

  bool get interactionEnabled;

  /// Whether the pointer hovers the control or it shows a keyboard focus highlight.
  bool get hovered => _hovered || _focusHighlighted;

  bool get pressed => _pressed;

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!interactionEnabled) {
      _hovered = false;
      _focusHighlighted = false;
      _pressed = false;
    }
  }

  /// Wraps [child] as a button. Pass `focusable: false` when the control already owns its focus,
  /// activation and semantics (for example a switch with its own [FocusableActionDetector]).
  ///
  /// [semanticLabel] names the button for assistive technology; icon-only controls must provide it.
  /// [toggled] reports an on/off state for toggle buttons and stays null for plain actions.
  Widget pointerRegion({
    required Widget child,
    required VoidCallback? onTap,
    HitTestBehavior? behavior,
    bool focusable = true,
    String? semanticLabel,
    bool? toggled,
  }) {
    final tap = withButtonHaptic(interactionEnabled ? onTap : null);
    final region = MouseRegion(
      onEnter: interactionEnabled ? (_) => _hover(true) : null,
      onExit: interactionEnabled ? (_) => _hover(false) : null,
      cursor: interactionEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: tap,
        onTapDown: interactionEnabled ? (_) => _press(true) : null,
        onTapUp: interactionEnabled ? (_) => _press(false) : null,
        onTapCancel: interactionEnabled ? () => _press(false) : null,
        behavior: behavior,
        child: child,
      ),
    );

    if (!focusable) {
      return region;
    }

    return Semantics(
      button: true,
      enabled: interactionEnabled,
      label: semanticLabel,
      toggled: toggled,
      child: FocusableActionDetector(
        enabled: interactionEnabled && tap != null,
        mouseCursor: MouseCursor.defer,
        onShowFocusHighlight: _focusHighlight,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => tap?.call())},
        child: region,
      ),
    );
  }

  void _hover(bool value) {
    if (_hovered != value) {
      setState(() => _hovered = value);
    }
  }

  void _focusHighlight(bool value) {
    if (_focusHighlighted != value) {
      setState(() => _focusHighlighted = value);
    }
  }

  void _press(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }
}

import 'package:flutter/material.dart';

/// Tracks the keyboard focus highlight of a descendant [InkWell].
///
/// The theme keeps ink focus overlays transparent, so controls built on [InkWell] pass
/// [handleInkFocusChange] to `InkWell.onFocusChange` and paint their own indicator while
/// [focusHighlighted]. Like Material, the highlight shows only in [FocusHighlightMode.traditional],
/// so touch and mouse interaction keep their existing visuals.
mixin InkFocusHighlight<T extends StatefulWidget> on State<T> {
  bool _inkFocused = false;
  FocusHighlightMode _highlightMode = FocusManager.instance.highlightMode;

  bool get focusHighlighted => _inkFocused && _highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();

    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);

    super.dispose();
  }

  void handleInkFocusChange(bool focused) {
    if (_inkFocused != focused) {
      setState(() => _inkFocused = focused);
    }
  }

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_highlightMode != mode) {
      setState(() => _highlightMode = mode);
    }
  }
}

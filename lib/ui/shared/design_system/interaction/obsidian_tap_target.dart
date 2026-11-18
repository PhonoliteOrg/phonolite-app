import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/obsidian_focus_ring.dart';

/// A custom-painted tappable region that behaves as a real button.
///
/// Besides the tap and click cursor, it joins focus traversal, activates with Enter/Space through
/// [ActivateIntent], is announced as a button, and draws a focus ring while keyboard-focused. Use
/// it instead of pairing a bare [MouseRegion] with a [GestureDetector], which is invisible to
/// keyboard and assistive-technology users.
class ObsidianTapTarget extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final String? semanticLabel;
  final HitTestBehavior behavior;
  final BorderRadius focusRingRadius;
  final Widget child;

  const ObsidianTapTarget({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.onHover,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
    this.focusRingRadius = const BorderRadius.all(Radius.circular(4)),
    required this.child,
  });

  @override
  State<ObsidianTapTarget> createState() => _ObsidianTapTargetState();
}

class _ObsidianTapTargetState extends State<ObsidianTapTarget> {
  bool _focusHighlighted = false;

  void _setFocusHighlighted(bool value) {
    if (_focusHighlighted != value) {
      setState(() => _focusHighlighted = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tap = withButtonHaptic(widget.onTap);
    final enabled = tap != null || widget.onLongPress != null;
    final onHover = widget.onHover;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: _setFocusHighlighted,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => tap?.call())},
        child: MouseRegion(
          onEnter: enabled && onHover != null ? (_) => onHover(true) : null,
          onExit: enabled && onHover != null ? (_) => onHover(false) : null,
          child: GestureDetector(
            onTap: tap,
            onLongPress: widget.onLongPress,
            behavior: widget.behavior,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: _focusHighlighted
                  ? obsidianFocusRing(borderRadius: widget.focusRingRadius)
                  : const BoxDecoration(),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

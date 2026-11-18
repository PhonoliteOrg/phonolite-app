import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_palette.dart';

/// A controlled, pill-shaped switch with a full touch target and keyboard access.
class ObsidianSwitch extends StatefulWidget {
  final bool value;
  final String semanticLabel;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  const ObsidianSwitch({
    super.key,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  bool get enabled => onChanged != null;

  @override
  State<ObsidianSwitch> createState() => _ObsidianSwitchState();
}

class _ObsidianSwitchState extends State<ObsidianSwitch> with PointerInteraction<ObsidianSwitch> {
  static const Duration _transition = Duration(milliseconds: 160);
  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false): ActivateIntent(),
  };

  bool _hasFocus = false;

  @override
  bool get interactionEnabled => widget.enabled;

  void _toggle() => widget.onChanged?.call(!widget.value);

  void _pointerActivate(BuildContext context) {
    Focus.of(context).requestFocus();
    _toggle();
  }

  void _activate() => withSelectionHaptic(widget.onChanged)?.call(!widget.value);

  void _focusChanged(bool focused) {
    setState(() => _hasFocus = focused);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final activationRepeat =
        event is KeyRepeatEvent &&
        (const SingleActivator(LogicalKeyboardKey.space).accepts(event, HardwareKeyboard.instance) ||
            const SingleActivator(LogicalKeyboardKey.enter).accepts(event, HardwareKeyboard.instance));

    return activationRepeat ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Widget _thumb(Duration duration) {
    final color = widget.value ? ObsidianPalette.obsidian : ObsidianPalette.textPrimary;
    final opacity = widget.enabled || widget.value ? 1.0 : 0.45;

    return AnimatedContainer(
      key: const ValueKey('obsidian-switch-thumb'),
      duration: duration,
      curve: Curves.easeOutCubic,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }

  Widget _track(Duration duration) {
    const surface = ObsidianPalette.obsidianElevated;
    final offColor = Color.alphaBlend(ObsidianPalette.border, surface);
    final trackColor = widget.value ? ObsidianPalette.gold : offColor;
    final enabledOpacity = pressed ? 0.8 : 1.0;
    final opacity = widget.enabled ? enabledOpacity : 0.35;
    final outline = ObsidianPalette.textMuted.withValues(alpha: widget.enabled ? 0.6 : 0.2);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      width: 52,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(trackColor.withValues(alpha: opacity), surface),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
        border: Border.all(color: widget.value ? Colors.transparent : outline),
      ),
      child: AnimatedAlign(
        alignment: widget.value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: _thumb(duration),
      ),
    );
  }

  Widget _control(Duration duration) => SizedBox(width: 60, height: 48, child: Center(child: _track(duration)));

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : _transition;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: widget.enabled,
      focusable: widget.enabled,
      focused: _hasFocus,
      onTap: widget.enabled ? _activate : null,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKeyEvent,
        child: FocusableActionDetector(
          enabled: widget.enabled,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          shortcuts: _shortcuts,
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate())},
          onFocusChange: _focusChanged,
          child: Builder(
            builder: (context) => pointerRegion(
              onTap: () => _pointerActivate(context),
              behavior: HitTestBehavior.opaque,
              // The switch owns focus, activation and toggle semantics above.
              focusable: false,
              child: _control(duration),
            ),
          ),
        ),
      ),
    );
  }
}

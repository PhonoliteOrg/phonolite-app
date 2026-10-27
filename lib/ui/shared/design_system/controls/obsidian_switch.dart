import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// A controlled, rectangular switch with a full touch target and keyboard access.
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

  Widget _surface({required Color fill, required Color border, required Widget child}) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      border: Border.all(color: border),
    ),
    child: child,
  );

  Widget _thumb() {
    final color = widget.value ? ObsidianPalette.gold : ObsidianPalette.textMuted;
    final fill = widget.enabled ? color : color.withValues(alpha: 0.3);

    return SizedBox(
      key: const ValueKey('obsidian-switch-thumb'),
      width: 20,
      height: 20,
      child: _surface(
        fill: fill,
        border: widget.enabled ? color : Colors.transparent,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < 2; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: ColoredBox(
                    color: ObsidianPalette.obsidian.withValues(alpha: widget.enabled ? 0.65 : 0.4),
                    child: const SizedBox(width: 1, height: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _track(Duration duration) {
    final highlighted = widget.enabled && pressed;
    final accent = widget.value || highlighted ? ObsidianPalette.gold : ObsidianPalette.textMuted;
    final enabledBorderOpacity = highlighted ? 1.0 : 0.6;
    final border = accent.withValues(alpha: widget.enabled ? enabledBorderOpacity : 0.2);

    return AnimatedContainer(
      duration: duration,
      decoration: BoxDecoration(
        boxShadow: [
          if (widget.enabled && (widget.value || highlighted))
            BoxShadow(color: ObsidianPalette.gold.withValues(alpha: highlighted ? 0.15 : 0.07), blurRadius: 10),
        ],
      ),
      child: _surface(
        fill: widget.value && widget.enabled
            ? Color.alphaBlend(ObsidianPalette.gold.withValues(alpha: 0.08), ObsidianPalette.obsidianElevated)
            : ObsidianPalette.obsidianElevated,
        border: border,
        child: SizedBox(
          width: 52,
          height: 26,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedAlign(
              alignment: widget.value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: _thumb(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(Duration duration) => SizedBox(
    width: 60,
    height: 48,
    child: Center(
      child: Padding(padding: const EdgeInsets.all(3), child: _track(duration)),
    ),
  );

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
              child: _control(duration),
            ),
          ),
        ),
      ),
    );
  }
}

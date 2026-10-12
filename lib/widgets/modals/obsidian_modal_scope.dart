import 'package:flutter/material.dart';

import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_theme.dart';

/// Modal controls keep their readable size even when the surrounding app scales
/// down for a phone. The user's system text scaling still applies.
class ObsidianModalScope extends StatelessWidget {
  const ObsidianModalScope({super.key, required this.builder});

  static const compactBreakpoint = 820.0;
  static const compactInset = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 16,
  );

  final WidgetBuilder builder;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;

  static bool usesTouchTargets(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ModalTouchTargets>()
          ?.enabled ??
      false;

  static EdgeInsets insetsOf(BuildContext context) =>
      isCompact(context) ? compactInset : const EdgeInsets.all(24);

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final child = _ModalTouchTargets(
      enabled: compact,
      child: Builder(builder: builder),
    );
    if (!compact) {
      return child;
    }
    return Theme(
      data: ObsidianTheme.build().copyWith(
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: ObsidianScale(scale: 1, child: child),
    );
  }
}

class _ModalTouchTargets extends InheritedWidget {
  const _ModalTouchTargets({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_ModalTouchTargets oldWidget) =>
      enabled != oldWidget.enabled;
}

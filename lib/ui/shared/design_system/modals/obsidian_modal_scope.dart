import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Modal controls keep their readable size even when the surrounding app scales
/// down for a phone. The user's system text scaling still applies.
class ObsidianModalScope extends StatelessWidget {
  static const double compactBreakpoint = 820.0;
  static const EdgeInsets compactInset = EdgeInsets.symmetric(horizontal: 12, vertical: 16);

  final WidgetBuilder builder;

  const ObsidianModalScope({super.key, required this.builder});

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < compactBreakpoint;

  static bool usesTouchTargets(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ModalTouchTargets>()?.enabled ?? false;

  static EdgeInsets insetsOf(BuildContext context) => isCompact(context) ? compactInset : const EdgeInsets.all(24);

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final platform = Theme.of(context).platform;
    final touchTargets =
        compact ||
        switch (platform) {
          TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
          _ => false,
        };
    final child = _ModalTouchTargets(
      enabled: touchTargets,
      child: Builder(builder: builder),
    );

    if (!touchTargets) {
      return child;
    }

    return Theme(
      data: ObsidianTheme.build().copyWith(
        platform: platform,
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: ObsidianScale(scale: 1, child: child),
    );
  }
}

class _ModalTouchTargets extends InheritedWidget {
  final bool enabled;

  const _ModalTouchTargets({required this.enabled, required super.child});

  @override
  bool updateShouldNotify(_ModalTouchTargets oldWidget) => enabled != oldWidget.enabled;
}

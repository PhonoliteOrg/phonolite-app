import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shell/navigation/base_app_navigation.dart';

class AppBottomNavigation extends BaseAppNavigation {
  static const double height = 64;

  const AppBottomNavigation({
    super.key,
    required super.destinations,
    required super.selectedIndex,
    required super.onDestinationSelected,
  });

  @override
  double get destinationSize => 56;

  @override
  double get destinationIconSize => 40;

  @override
  Border surfaceBorder(BuildContext context) => Border(top: navigationBorder);

  @override
  double surfaceHeight(BuildContext context) => height + MediaQuery.paddingOf(context).bottom;

  @override
  EdgeInsetsGeometry surfacePadding(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return EdgeInsets.only(bottom: padding.bottom, left: padding.left, right: padding.right);
  }

  @override
  Widget decorateNavigation(BuildContext context, Widget surface) =>
      Theme.of(context).platform == TargetPlatform.iOS ? ObsidianGlassSurface(child: surface) : surface;

  @override
  Widget navigationContent(BuildContext context, List<Widget> items) => Center(
    child: Row(
      children: [for (final item in items) Expanded(child: Center(child: item))],
    ),
  );
}

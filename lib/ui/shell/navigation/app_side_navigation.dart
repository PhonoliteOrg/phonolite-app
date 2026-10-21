import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shell/navigation/base_app_navigation.dart';

class AppSideNavigation extends BaseAppNavigation {
  const AppSideNavigation({
    super.key,
    required super.destinations,
    required super.selectedIndex,
    required super.onDestinationSelected,
  });

  @override
  Border surfaceBorder(BuildContext context) => Border(right: navigationBorder);

  @override
  Widget decorateNavigation(BuildContext context, Widget surface) =>
      SizedBox(width: 64 * ObsidianScale.of(context), child: surface);

  @override
  Widget navigationContent(BuildContext context, List<Widget> items) {
    final scale = ObsidianScale.of(context);
    final edgeToEdge = Theme.of(context).platform == TargetPlatform.iOS;

    return SafeArea(
      top: edgeToEdge,
      bottom: edgeToEdge,
      left: edgeToEdge,
      right: false,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (final item in items) ...[item, SizedBox(height: 12 * scale)],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_nav_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// App destinations and selection presentation, independent of page toolbars.
abstract class BaseAppNavigation extends StatelessWidget {
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const BaseAppNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @protected
  Color get navigationBackground => const Color(0x40000000);

  @protected
  BorderSide get navigationBorder => const BorderSide(color: ObsidianPalette.border);

  @protected
  double get destinationSize => 52;

  @protected
  double get destinationIconSize => 32;

  @protected
  Border surfaceBorder(BuildContext context);

  @protected
  double? surfaceHeight(BuildContext context) => null;

  @protected
  EdgeInsetsGeometry? surfacePadding(BuildContext context) => null;

  @protected
  Widget destinationContent(BuildContext context, int index) {
    final destination = destinations[index];

    return ObsidianNavIcon(
      icon: destination.selectedIcon ?? destination.icon,
      isSelected: index == selectedIndex,
      label: destination.label,
      onTap: () => onDestinationSelected(index),
      size: destinationSize,
      iconSize: destinationIconSize,
    );
  }

  @protected
  Widget navigationContent(BuildContext context, List<Widget> items);

  @protected
  Widget decorateNavigation(BuildContext context, Widget surface) => surface;

  @override
  @nonVirtual
  Widget build(BuildContext context) => decorateNavigation(
    context,
    Container(
      height: surfaceHeight(context),
      padding: surfacePadding(context),
      decoration: BoxDecoration(color: navigationBackground, border: surfaceBorder(context)),
      child: navigationContent(context, [
        for (var index = 0; index < destinations.length; index++) destinationContent(context, index),
      ]),
    ),
  );
}

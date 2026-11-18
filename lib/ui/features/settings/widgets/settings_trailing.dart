import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';

class SettingsTrailing extends StatelessWidget {
  static const double slotWidth = 60;

  final Widget child;

  const SettingsTrailing({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: isCompactListWidth(context) ? 32 : 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: slotWidth),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    ),
  );
}

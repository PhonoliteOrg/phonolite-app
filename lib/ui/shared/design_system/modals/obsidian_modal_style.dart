import 'package:flutter/material.dart';

abstract final class ObsidianModalStyle {
  static final Color sheetBarrierColor = Colors.black.withValues(alpha: 0.45);
  static const EdgeInsets insetPadding = EdgeInsets.all(24);
  static const EdgeInsets titlePadding = EdgeInsets.fromLTRB(24, 20, 24, 0);
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(24, 16, 24, 0);
  static const EdgeInsets actionsPadding = EdgeInsets.fromLTRB(24, 12, 24, 16);
  static const double actionSpacing = 8.0;

  static TextStyle? titleStyle(BuildContext context) =>
      DialogTheme.of(context).titleTextStyle ?? Theme.of(context).textTheme.titleLarge;

  static TextStyle? bodyStyle(BuildContext context) =>
      DialogTheme.of(context).contentTextStyle ?? Theme.of(context).textTheme.bodyMedium;
}

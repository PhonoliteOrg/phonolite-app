import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/settings/widgets/settings_trailing.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';

Widget buildSettingsRow(
  BuildContext context, {
  required Widget leading,
  required String title,
  String? subtitle,
  int? subtitleMaxLines = 1,
  Widget? trailing,
  VoidCallback? onTap,
  Color? titleColor,
}) {
  final isCompact = isCompactListWidth(context);

  return ObsidianListRow(
    title: title,
    titleMaxLines: null,
    subtitle: subtitle?.trim().isNotEmpty == true ? subtitle : null,
    subtitleMaxLines: isCompact ? null : subtitleMaxLines,
    titleColor: titleColor,
    onTap: onTap,
    enabled: onTap != null,
    showHover: onTap != null,
    leadingGap: isCompact ? 8 : 12,
    leading: SizedBox(
      width: isCompact ? 28 : 32,
      child: Center(
        child: IconTheme.merge(
          data: IconThemeData(size: isCompact ? 20 : 24),
          child: leading,
        ),
      ),
    ),
    trailing: trailing == null
        ? null
        : IconTheme.merge(
            data: IconThemeData(size: isCompact ? 22 : 24),
            child: SettingsTrailing(child: trailing),
          ),
  );
}

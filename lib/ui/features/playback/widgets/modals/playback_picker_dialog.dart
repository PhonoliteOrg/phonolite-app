import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_alert_dialog.dart';

Future<T?> showPlaybackPicker<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder contentBuilder,
  bool scrollable = false,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => ObsidianAlertDialog(
      title: Text(title),
      scrollable: scrollable,
      content: SizedBox(width: context.s(320), child: contentBuilder(context)),
    ),
  );
}

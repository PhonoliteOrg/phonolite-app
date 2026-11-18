import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

Widget playbackTechTagRow(BuildContext context, List<Widget> tags, {bool center = false, bool wrap = false}) {
  if (tags.isEmpty) {
    return const SizedBox.shrink();
  }

  final s = context.s;

  if (wrap) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        runAlignment: center ? WrapAlignment.center : WrapAlignment.start,
        spacing: s(6),
        runSpacing: s(4),
        children: tags,
      ),
    );
  }

  return ConstrainedBox(
    constraints: BoxConstraints(minHeight: s(16)),
    child: ClipRect(
      child: Align(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tags.length; i++) ...[if (i > 0) SizedBox(width: s(6)), tags[i]],
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

class StatsEmptyText extends StatelessWidget {
  final String text;

  const StatsEmptyText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => EmptyStateText(
    title: text,
    padding: EdgeInsets.symmetric(vertical: context.s(12)),
  );
}

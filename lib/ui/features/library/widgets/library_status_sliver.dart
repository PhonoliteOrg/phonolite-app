import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shell/page_sliver_box.dart';

/// Status copy for both local and connected library search sections.
class LibraryStatusSliver extends StatelessWidget {
  final String message;

  const LibraryStatusSliver({super.key, required this.message});

  @override
  Widget build(BuildContext context) => PageSliverBox(
    top: 24,
    child: EmptyStateText(title: message, padding: EdgeInsets.zero),
  );
}

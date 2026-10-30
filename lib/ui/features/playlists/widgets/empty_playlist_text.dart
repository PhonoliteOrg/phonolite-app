import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';

class EmptyPlaylistText extends StatelessWidget {
  const EmptyPlaylistText({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyStateText(title: 'No tracks yet.');
  }
}

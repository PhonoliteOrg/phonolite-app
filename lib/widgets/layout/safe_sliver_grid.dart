import 'package:flutter/material.dart';

class SafeSliverGrid extends StatelessWidget {
  const SafeSliverGrid({
    super.key,
    required this.gridDelegate,
    required this.delegate,
  });

  final SliverGridDelegate gridDelegate;
  final SliverChildDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        if (constraints.crossAxisExtent <= 0 ||
            constraints.viewportMainAxisExtent <= 0) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverGrid(gridDelegate: gridDelegate, delegate: delegate);
      },
    );
  }
}

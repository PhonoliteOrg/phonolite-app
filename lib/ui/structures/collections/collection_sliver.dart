import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/safe_sliver_grid.dart';

typedef CollectionItemBuilder<T> = Widget Function(BuildContext context, T item, bool isListView);

/// Shared lazy collection layout. Item families supply the row/card content.
class CollectionSliver<T> extends StatelessWidget {
  static const SliverGridDelegateWithMaxCrossAxisExtent standardGrid = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 240,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: 0.82,
  );

  final List<T> items;
  final bool isListView;
  final CollectionItemBuilder<T> itemBuilder;
  final SliverGridDelegate gridDelegate;
  final IndexedWidgetBuilder separatorBuilder;

  const CollectionSliver({
    super.key,
    required this.items,
    required this.isListView,
    required this.itemBuilder,
    this.gridDelegate = standardGrid,
    this.separatorBuilder = _divider,
  });

  static Widget _divider(BuildContext context, int index) => const Divider(height: 1);

  @override
  Widget build(BuildContext context) {
    if (isListView) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index.isOdd) {
            return separatorBuilder(context, index ~/ 2);
          }

          return itemBuilder(context, items[index ~/ 2], true);
        }, childCount: items.isEmpty ? 0 : items.length * 2 - 1),
      );
    }

    return SafeSliverGrid(
      gridDelegate: gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, index) => itemBuilder(context, items[index], false),
        childCount: items.length,
      ),
    );
  }
}

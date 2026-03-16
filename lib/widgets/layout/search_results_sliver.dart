import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../display/search_result_tile.dart';

class SearchResultsSliver extends StatelessWidget {
  const SearchResultsSliver({
    super.key,
    required this.results,
    required this.onSelect,
  });

  final List<SearchResult> results;
  final ValueChanged<SearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final itemCount = results.isEmpty ? 0 : results.length * 2 - 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) {
          return const Divider(height: 1);
        }
        final result = results[index ~/ 2];
        return SearchResultTile(result: result, onTap: () => onSelect(result));
      }, childCount: itemCount),
    );
  }
}

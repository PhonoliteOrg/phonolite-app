import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_result_tile.dart';

class SearchResultsSliver extends StatelessWidget {
  final List<SearchResult> results;
  final ValueChanged<SearchResult> onSelect;
  final CatalogController? catalog;
  final Map<String, String> headers;
  final bool useLocalArtwork;

  const SearchResultsSliver({
    super.key,
    required this.results,
    required this.onSelect,
    this.catalog,
    this.headers = const {},
    this.useLocalArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = results.isEmpty ? 0 : results.length * 2 - 1;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) {
          return const Divider(height: 1);
        }

        final result = results[index ~/ 2];

        return SearchResultTile(
          result: result,
          catalog: catalog,
          headers: headers,
          useLocalArtwork: useLocalArtwork,
          onTap: () => onSelect(result),
        );
      }, childCount: itemCount),
    );
  }
}

import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../../entities/server_connection.dart';
import '../display/search_result_tile.dart';

class SearchResultsSliver extends StatelessWidget {
  const SearchResultsSliver({
    super.key,
    required this.results,
    required this.onSelect,
    this.connection,
    this.headers = const {},
    this.useLocalArtwork = false,
  });

  final List<SearchResult> results;
  final ValueChanged<SearchResult> onSelect;
  final ServerConnection? connection;
  final Map<String, String> headers;
  final bool useLocalArtwork;

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
          connection: connection,
          headers: headers,
          useLocalArtwork: useLocalArtwork,
          onTap: () => onSelect(result),
        );
      }, childCount: itemCount),
    );
  }
}

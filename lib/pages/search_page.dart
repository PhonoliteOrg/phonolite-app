import 'package:flutter/material.dart';

import '../entities/models.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/search_result_tile.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/inputs/search_filter_chips.dart';
import '../widgets/inputs/search_hud.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ObsidianSectionHeader(
            title: 'Search',
            subtitle: 'Scan the library',
          ),
          const SizedBox(height: 16),
          SearchHud(
            controller: _controller,
            onSubmit: () =>
                controller.search(_controller.text.trim(), filter: _filter),
            onClear: () => controller.search('', filter: _filter),
          ),
          const SizedBox(height: 12),
          SearchFilterChips(
            activeFilter: _filter,
            onChanged: (filter) {
              setState(() => _filter = filter);
              if (_controller.text.trim().isNotEmpty) {
                controller.search(_controller.text.trim(), filter: _filter);
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<SearchResult>>(
              stream: controller.searchStream,
              initialData: controller.searchResults,
              builder: (context, snapshot) {
                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return const EmptyState(
                    title: 'No results',
                    message: 'Try another search term.',
                  );
                }
                return GlassPanel(
                  cut: 18,
                  padding: const EdgeInsets.all(8),
                  child: ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => Divider(
                      color: ObsidianPalette.border.withOpacity(0.6),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return SearchResultTile(
                        result: result,
                        onTap: () => controller.selectSearchResult(result),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

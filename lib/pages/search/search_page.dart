import 'package:flutter/material.dart' hide SearchController;

import 'package:phonolite_app/application/controllers/search/search_controller.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_filter_chips.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_result_tile.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/base_page_toolbar.dart';

class SearchPage extends BasePage {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends BasePageState<SearchPage> {
  late final SearchController _feature = bindController(SearchController(AppScope.of(context)));
  late final TextEditingController _controller;

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 20, 20, 16);

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
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return assemble(
      context,
      navbar: const PageToolbar(
        title: ObsidianSectionHeader(title: 'Search', subtitle: 'Scan the library'),
      ),
      body: PageBody.box(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SearchHud(
              controller: _controller,
              onSubmit: () => _feature.submit(_controller.text),
              onClear: () => _feature.clear(),
            ),
            const SizedBox(height: 12),
            SearchFilterChips(
              activeFilter: _feature.filter,
              onChanged: (filter) => _feature.selectFilter(filter, _controller.text),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<SearchResult>>(
                stream: controller.searchStream,
                initialData: controller.searchResults,
                builder: (context, snapshot) {
                  final results = snapshot.data ?? [];

                  if (results.isEmpty) {
                    return const EmptyStateText(title: 'No results', message: 'Try another search term.');
                  }

                  return GlassPanel(
                    cut: 18,
                    padding: const EdgeInsets.all(8),
                    child: ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: ObsidianPalette.border.withByteOpacity(0.6), height: 1),
                      itemBuilder: (context, index) {
                        final result = results[index];

                        return SearchResultTile(
                          result: result,
                          catalog: controller.catalog,
                          headers: authHeaders(controller),
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
      ),
    );
  }
}

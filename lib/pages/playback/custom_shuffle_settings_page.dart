import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/playback/custom_shuffle_controller.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_choice_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_toggle_option.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/server_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/structures/sections/selection_sliver_section.dart';

enum _CustomShuffleView { artists, genres }

class CustomShuffleSettingsPage extends BasePage {
  static const String routeName = '/settings/custom-shuffle';

  const CustomShuffleSettingsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const CustomShuffleSettingsPage(),
    );
  }

  @override
  State<CustomShuffleSettingsPage> createState() => _CustomShuffleSettingsPageState();
}

class _CustomShuffleSettingsPageState extends BasePageState<CustomShuffleSettingsPage> {
  late final CustomShuffleController _feature = bindController(CustomShuffleController(AppScope.of(context)));
  final TextEditingController _artistSearchController = TextEditingController();
  final TextEditingController _genreSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _CustomShuffleView _view = _CustomShuffleView.artists;

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.only(bottom: 8);

  @override
  void initState() {
    super.initState();

    _artistSearchController.addListener(() => _feature.handleArtistSearchChanged(_artistSearchController.text));
    _genreSearchController.addListener(() => _feature.setGenreQuery(_genreSearchController.text));
    _scrollController.addListener(_handleArtistScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreArtists());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleArtistScroll);
    _scrollController.dispose();
    _artistSearchController.dispose();
    _genreSearchController.dispose();

    super.dispose();
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 1.1),
    );
  }

  Widget _buildTargetToggle() {
    final showingServer = _feature.target == CustomShuffleTarget.server;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('LIBRARY'),
        const SizedBox(height: 6),
        Wrap(
          children: [
            _buildToggleOption(
              label: 'Server',
              icon: const ServerIcon(),
              isActive: showingServer,
              onTap: () => _feature.setTarget(CustomShuffleTarget.server),
            ),
            _buildToggleOption(
              label: 'Local',
              icon: const Icon(PhonoliteIcons.download),
              isActive: !showingServer,
              onTap: () => _feature.setTarget(CustomShuffleTarget.local),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewToggle() {
    final showingArtists = _view == _CustomShuffleView.artists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('FILTER BY'),
        const SizedBox(height: 6),
        Wrap(
          children: [
            _buildToggleOption(
              label: 'Artists',
              icon: const Icon(PhonoliteIcons.usersRound),
              isActive: showingArtists,
              onTap: () => setState(() => _view = _CustomShuffleView.artists),
            ),
            _buildToggleOption(
              label: 'Genres',
              icon: const Icon(PhonoliteIcons.tag),
              isActive: !showingArtists,
              onTap: _showGenres,
            ),
          ],
        ),
      ],
    );
  }

  void _showGenres() {
    setState(() => _view = _CustomShuffleView.genres);

    _feature.prepareGenreOptions();
  }

  Widget _buildToggleOption({
    required String label,
    required Widget icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return ObsidianToggleOption(label: label, icon: icon, isActive: isActive, onPressed: onTap);
  }

  Widget _buildArtistList({
    required bool canLoadArtists,
    required List<Artist> artists,
    required int fullCount,
    required bool isLoading,
    required bool hasMoreArtists,
  }) {
    if (!canLoadArtists) {
      return _buildInlineMessage('Connect to a server to load artists.');
    }

    if (isLoading && fullCount == 0) {
      return _buildLoadingIndicator();
    }

    if (fullCount == 0) {
      return _buildInlineMessage('No artists available.');
    }

    if (artists.isEmpty) {
      if (isLoading || hasMoreArtists) {
        return _buildLoadingIndicator();
      }

      return _buildInlineMessage('No artists match your search.');
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverList.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            final selected = _feature.activeArtistSelection.contains(artist.id);

            return ObsidianChoiceRow(
              title: artist.name,
              selected: selected,
              onTap: () => _feature.toggleArtist(artist.id),
            );
          },
        ),
        if (isLoading) _buildLoadingIndicator(verticalPadding: 16),
      ],
    );
  }

  Widget _buildGenreList({
    required bool canLoadArtists,
    required List<GenreOption> genres,
    required int fullCount,
    required bool isLoading,
    required bool hasMoreArtists,
  }) {
    if (!canLoadArtists) {
      return _buildInlineMessage('Connect to a server to load genres.');
    }

    if (isLoading || hasMoreArtists) {
      return _buildLoadingIndicator();
    }

    if (fullCount == 0) {
      return _buildInlineMessage('No genres available.');
    }

    if (genres.isEmpty) {
      return _buildInlineMessage('No genres match your search.');
    }

    return SliverList.builder(
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        final selected = _feature.activeGenreSelection.contains(genre.key);

        return ObsidianChoiceRow(title: genre.label, selected: selected, onTap: () => _feature.toggleGenre(genre.key));
      },
    );
  }

  Widget _buildLoadingIndicator({double verticalPadding = 24}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildInlineMessage(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted)),
      ),
    );
  }

  void _maybeLoadMoreArtists() {
    if (mounted && _scrollController.hasClients && _scrollController.position.hasContentDimensions) {
      _feature.loadMoreArtists(
        _scrollController.position.extentAfter,
        showingArtists: _view == _CustomShuffleView.artists,
      );
    }
  }

  void _handleArtistScroll() {
    _maybeLoadMoreArtists();
  }

  Widget _shuffleIntroduction(BuildContext context) => SliverToBoxAdapter(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick artists and genres used for library shuffles.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
        ),
        const SizedBox(height: 24),
        Wrap(spacing: 32, runSpacing: 16, children: [_buildTargetToggle(), _buildViewToggle()]),
        const SizedBox(height: 20),
      ],
    ),
  );

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);
    final canUseServerArtists = controller.authState.isAuthorized;

    return StreamBuilder<OfflineLibrarySnapshot>(
      stream: controller.offlineLibrarySnapshotStream,
      initialData: controller.offlineLibrarySnapshot,
      builder: (context, _) {
        final localArtists = controller.offlineLibrarySnapshot.artistGroups
            .map((group) => group.toArtist())
            .toList(growable: false);

        return StreamBuilder<List<Artist>>(
          stream: controller.artistsStream,
          initialData: controller.artists,
          builder: (context, snapshot) {
            final serverArtists = snapshot.data ?? <Artist>[];
            final artists = _feature.showingServerTarget ? serverArtists : localArtists;

            final filteredArtists = _feature.filterArtists(artists);

            final genreOptions = _feature.buildGenreOptions(artists);
            final filteredGenres = _feature.filterGenres(genreOptions);

            return StreamBuilder<bool>(
              stream: controller.artistsLoadingStream,
              initialData: controller.artistsLoading,
              builder: (context, loadingSnapshot) {
                final serverLoading = loadingSnapshot.data ?? false;
                final isLoading = _feature.showingServerTarget && serverLoading;
                final hasMoreArtists = _feature.showingServerTarget && controller.hasMoreArtists;
                final canUseArtists = _feature.showingServerTarget ? canUseServerArtists : true;
                final showingArtists = _view == _CustomShuffleView.artists;

                if (_feature.showingServerTarget &&
                    showingArtists &&
                    artists.isNotEmpty &&
                    hasMoreArtists &&
                    !isLoading &&
                    _artistSearchController.text.trim().isEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreArtists());
                }

                return assemble(
                  context,
                  navbar: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailActionHeader(backLabel: 'Back to settings', onBack: () => Navigator.of(context).pop()),
                      const SizedBox(height: 16),
                      const LibraryHeader(title: 'CUSTOM SHUFFLE', maxLines: 2),
                    ],
                  ),
                  body: PageBody.slivers(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    slivers: [
                      _shuffleIntroduction(context),
                      if (showingArtists) ...[
                        SelectionSliverSection(
                          onSearch: () => setState(() {}),
                          title: 'Artists',
                          controller: _artistSearchController,
                          hintText: 'Search artists',
                          summary: hasMoreArtists
                              ? 'Selected ${_feature.activeArtistSelection.length} of loaded ${artists.length}'
                              : 'Selected ${_feature.activeArtistSelection.length} of ${artists.length}',
                          onSelectAll: !canUseArtists || (artists.isEmpty && !hasMoreArtists)
                              ? null
                              : _feature.selectAllAvailableArtists,
                          onClear: !canUseArtists || _feature.activeArtistSelection.isEmpty
                              ? null
                              : _feature.clearArtists,
                          sliver: _buildArtistList(
                            canLoadArtists: canUseArtists,
                            artists: filteredArtists,
                            fullCount: artists.length,
                            isLoading: isLoading,
                            hasMoreArtists: hasMoreArtists,
                          ),
                        ),
                      ] else ...[
                        SelectionSliverSection(
                          onSearch: () => setState(() {}),
                          title: 'Genres',
                          controller: _genreSearchController,
                          hintText: 'Search genres',
                          summary: 'Selected ${_feature.activeGenreSelection.length} of ${genreOptions.length}',
                          onSelectAll: !canUseArtists || genreOptions.isEmpty
                              ? null
                              : () => _feature.selectAllGenres(genreOptions),
                          onClear: !canUseArtists || _feature.activeGenreSelection.isEmpty
                              ? null
                              : _feature.clearGenres,
                          sliver: _buildGenreList(
                            canLoadArtists: canUseArtists,
                            genres: filteredGenres,
                            fullCount: genreOptions.length,
                            isLoading: isLoading,
                            hasMoreArtists: hasMoreArtists,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

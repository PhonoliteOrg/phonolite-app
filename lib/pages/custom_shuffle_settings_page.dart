import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';
import '../widgets/ui/server_icon.dart';

import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/genre_text.dart';
import '../widgets/inputs/lucide_checkbox.dart';
import '../widgets/inputs/obsidian_toggle_option.dart';
import '../widgets/inputs/search_hud.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/playback_content_inset.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/hover_row.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/responsive_breakpoints.dart';
import '../widgets/ui/tech_button.dart';

class CustomShuffleSettingsPage extends StatefulWidget {
  const CustomShuffleSettingsPage({super.key});

  static const routeName = '/settings/custom-shuffle';

  static Route<void> route() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const CustomShuffleSettingsPage(),
    );
  }

  @override
  State<CustomShuffleSettingsPage> createState() =>
      _CustomShuffleSettingsPageState();
}

enum _CustomShuffleView { artists, genres }

enum _CustomShuffleTarget { server, local }

class _GenreOption {
  const _GenreOption({required this.key, required this.label});

  final String key;
  final String label;
}

class _CustomShuffleSettingsPageState extends State<CustomShuffleSettingsPage> {
  final TextEditingController _artistSearchController = TextEditingController();
  final TextEditingController _genreSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedArtistIds = <String>{};
  final Set<String> _selectedGenres = <String>{};
  final Set<String> _selectedLocalArtistIds = <String>{};
  final Set<String> _selectedLocalGenres = <String>{};
  _CustomShuffleTarget _target = _CustomShuffleTarget.server;
  _CustomShuffleView _view = _CustomShuffleView.artists;
  Timer? _saveDebounce;
  Future<void> _saveChain = Future.value();
  AppController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _artistSearchController.addListener(_handleArtistSearchChanged);
    _genreSearchController.addListener(() => setState(() {}));
    _scrollController.addListener(_handleArtistScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _controller ??= AppScope.of(context);
    final settings = _controller!.customShuffleSettings;
    _selectedArtistIds.addAll(settings.artistIds);
    _selectedGenres.addAll(
      settings.genres.map(_normalizeGenre).where((genre) => genre.isNotEmpty),
    );
    _selectedLocalArtistIds.addAll(settings.localArtistIds);
    _selectedLocalGenres.addAll(
      settings.localGenres
          .map(_normalizeGenre)
          .where((genre) => genre.isNotEmpty),
    );
    if (_controller!.authState.isAuthorized && _controller!.artists.isEmpty) {
      unawaited(_controller!.loadArtists());
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadMoreArtists(),
    );
    _initialized = true;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _flushSave();
    _scrollController
      ..removeListener(_handleArtistScroll)
      ..dispose();
    _artistSearchController.dispose();
    _genreSearchController.dispose();
    super.dispose();
  }

  Set<String> get _activeArtistSelection =>
      _target == _CustomShuffleTarget.server
      ? _selectedArtistIds
      : _selectedLocalArtistIds;

  Set<String> get _activeGenreSelection =>
      _target == _CustomShuffleTarget.server
      ? _selectedGenres
      : _selectedLocalGenres;

  bool get _showingServerTarget => _target == _CustomShuffleTarget.server;

  void _toggleArtist(String artistId) {
    setState(() {
      final selection = _activeArtistSelection;
      if (selection.contains(artistId)) {
        selection.remove(artistId);
      } else {
        selection.add(artistId);
      }
    });
    _scheduleSave();
  }

  void _selectAllArtists(List<Artist> artists) {
    setState(() {
      _activeArtistSelection
        ..clear()
        ..addAll(artists.map((artist) => artist.id));
    });
    _scheduleSave();
  }

  Future<void> _selectAllAvailableArtists() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (!_showingServerTarget) {
      final localArtists = controller.offlineLibrarySnapshot.artistGroups
          .map((group) => group.toArtist())
          .toList(growable: false);
      _selectAllArtists(localArtists);
      return;
    }
    await controller.loadAllArtists();
    if (!mounted) {
      return;
    }
    _selectAllArtists(controller.artists);
  }

  void _clearArtists() {
    setState(() => _activeArtistSelection.clear());
    _scheduleSave();
  }

  void _toggleGenre(String genreKey) {
    setState(() {
      final selection = _activeGenreSelection;
      if (selection.contains(genreKey)) {
        selection.remove(genreKey);
      } else {
        selection.add(genreKey);
      }
    });
    _scheduleSave();
  }

  void _selectAllGenres(List<_GenreOption> genres) {
    setState(() {
      _activeGenreSelection
        ..clear()
        ..addAll(genres.map((genre) => genre.key));
    });
    _scheduleSave();
  }

  void _clearGenres() {
    setState(() => _activeGenreSelection.clear());
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), _flushSave);
  }

  void _handleArtistSearchChanged() {
    setState(() {});
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (!_showingServerTarget) {
      return;
    }
    if (_artistSearchController.text.trim().isNotEmpty &&
        controller.hasMoreArtists &&
        !controller.artistsLoading) {
      unawaited(controller.loadAllArtists());
    }
  }

  void _flushSave() {
    if (!_initialized) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final artistIds = _selectedArtistIds.toList();
    final genres = _selectedGenres.toList()..sort();
    final localArtistIds = _selectedLocalArtistIds.toList();
    final localGenres = _selectedLocalGenres.toList()..sort();
    _saveChain = _saveChain.then(
      (_) => controller.updateCustomShuffleSettings(
        artistIds: artistIds,
        genres: genres,
        localArtistIds: localArtistIds,
        localGenres: localGenres,
      ),
    );
  }

  List<Artist> _filterArtists(List<Artist> artists) {
    final query = _artistSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return artists;
    }
    return artists
        .where((artist) => artist.name.toLowerCase().contains(query))
        .toList();
  }

  List<_GenreOption> _buildGenreOptions(List<Artist> artists) {
    final labels = <String, String>{};
    for (final artist in artists) {
      for (final genre in artist.genres) {
        final normalized = _normalizeGenre(genre);
        if (normalized.isEmpty) {
          continue;
        }
        labels.putIfAbsent(normalized, () => genre.trim());
      }
    }
    for (final selected in _activeGenreSelection) {
      if (selected.trim().isEmpty) {
        continue;
      }
      labels.putIfAbsent(selected, () => selected);
    }
    final options = labels.entries
        .map(
          (entry) => _GenreOption(
            key: entry.key,
            label: genreDisplayLabel(entry.value),
          ),
        )
        .toList();
    options.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return options;
  }

  List<_GenreOption> _filterGenres(List<_GenreOption> genres) {
    final query = _genreSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return genres;
    }
    return genres
        .where((genre) => genre.label.toLowerCase().contains(query))
        .toList();
  }

  String _normalizeGenre(String genre) => genre.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final canUseServerArtists = controller.authState.isAuthorized;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Object?>(
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
                final artists = _showingServerTarget
                    ? serverArtists
                    : localArtists;
                final filteredArtists = _filterArtists(artists);
                final genreOptions = _buildGenreOptions(artists);
                final filteredGenres = _filterGenres(genreOptions);
                return StreamBuilder<bool>(
                  stream: controller.artistsLoadingStream,
                  initialData: controller.artistsLoading,
                  builder: (context, loadingSnapshot) {
                    final serverLoading = loadingSnapshot.data ?? false;
                    final isLoading = _showingServerTarget && serverLoading;
                    final hasMoreArtists =
                        _showingServerTarget && controller.hasMoreArtists;
                    final canUseArtists = _showingServerTarget
                        ? canUseServerArtists
                        : true;
                    final showingArtists = _view == _CustomShuffleView.artists;
                    if (_showingServerTarget &&
                        showingArtists &&
                        artists.isNotEmpty &&
                        hasMoreArtists &&
                        !isLoading &&
                        _artistSearchController.text.trim().isEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _maybeLoadMoreArtists(),
                      );
                    }
                    return CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            20 + PlaybackContentInset.topOf(context),
                            20,
                            20 + PlaybackContentInset.bottomOf(context),
                          ),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    CommandLinkButton(
                                      label: 'Back to settings',
                                      onTap: () => Navigator.of(context).pop(),
                                    ),
                                    const SizedBox(height: 16),
                                    const LibraryHeader(
                                      title: 'CUSTOM SHUFFLE',
                                      moduleCount: 0,
                                      maxLines: 2,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Pick artists and genres used for library shuffles.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: ObsidianPalette.textMuted,
                                          ),
                                    ),
                                    const SizedBox(height: 24),
                                    Wrap(
                                      spacing: 32,
                                      runSpacing: 16,
                                      children: [
                                        _buildTargetToggle(),
                                        _buildViewToggle(),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                              if (showingArtists) ...[
                                _buildSelectionSection(
                                  title: 'Artists',
                                  controller: _artistSearchController,
                                  hintText: 'Search artists',
                                  summary: hasMoreArtists
                                      ? 'Selected ${_activeArtistSelection.length} of loaded ${artists.length}'
                                      : 'Selected ${_activeArtistSelection.length} of ${artists.length}',
                                  onSelectAll:
                                      !canUseArtists ||
                                          (artists.isEmpty && !hasMoreArtists)
                                      ? null
                                      : _selectAllAvailableArtists,
                                  onClear:
                                      !canUseArtists ||
                                          _activeArtistSelection.isEmpty
                                      ? null
                                      : _clearArtists,
                                  sliver: _buildArtistList(
                                    canLoadArtists: canUseArtists,
                                    artists: filteredArtists,
                                    fullCount: artists.length,
                                    isLoading: isLoading,
                                    hasMoreArtists: hasMoreArtists,
                                  ),
                                ),
                              ] else ...[
                                _buildSelectionSection(
                                  title: 'Genres',
                                  controller: _genreSearchController,
                                  hintText: 'Search genres',
                                  summary:
                                      'Selected ${_activeGenreSelection.length} of ${genreOptions.length}',
                                  onSelectAll:
                                      !canUseArtists || genreOptions.isEmpty
                                      ? null
                                      : () => _selectAllGenres(genreOptions),
                                  onClear:
                                      !canUseArtists ||
                                          _activeGenreSelection.isEmpty
                                      ? null
                                      : _clearGenres,
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
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectionSection({
    required String title,
    required TextEditingController controller,
    required String hintText,
    required String summary,
    required VoidCallback? onSelectAll,
    required VoidCallback? onClear,
    required Widget sliver,
  }) {
    final compact = isCompactListWidth(context);
    return SliverPadding(
      padding: EdgeInsets.all(compact ? 12 : 20),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ObsidianSectionHeader(title: title),
                const SizedBox(height: 16),
                SearchHud(
                  controller: controller,
                  hintText: hintText,
                  height: 48,
                  onSubmit: () => setState(() {}),
                  onClear: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _buildSelectionActions(
                  summary: summary,
                  onSelectAll: onSelectAll,
                  onClear: onClear,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          sliver,
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: ObsidianPalette.textMuted,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildSelectionActions({
    required String summary,
    required VoidCallback? onSelectAll,
    required VoidCallback? onClear,
  }) {
    final count = Text(
      summary,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TechButton(
          label: 'Select all',
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onSelectAll,
        ),
        TechButton(
          label: 'Clear',
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: onClear,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [count, const SizedBox(height: 8), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: count),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildTargetToggle() {
    final showingServer = _target == _CustomShuffleTarget.server;
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
              onTap: () =>
                  setState(() => _target = _CustomShuffleTarget.server),
            ),
            _buildToggleOption(
              label: 'Local',
              icon: const Icon(PhonoliteIcons.download),
              isActive: !showingServer,
              onTap: () => setState(() => _target = _CustomShuffleTarget.local),
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
              onTap: () {
                setState(() => _view = _CustomShuffleView.genres);
                final controller = _controller;
                if (_showingServerTarget &&
                    controller != null &&
                    controller.hasMoreArtists) {
                  unawaited(controller.loadAllArtists());
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggleOption({
    required String label,
    required Widget icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return ObsidianToggleOption(
      label: label,
      icon: icon,
      isActive: isActive,
      onPressed: onTap,
    );
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
            final selected = _activeArtistSelection.contains(artist.id);
            return _buildSelectableRow(
              title: artist.name,
              selected: selected,
              onTap: () => _toggleArtist(artist.id),
            );
          },
        ),
        if (isLoading) _buildLoadingIndicator(verticalPadding: 16),
      ],
    );
  }

  Widget _buildGenreList({
    required bool canLoadArtists,
    required List<_GenreOption> genres,
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
        final selected = _activeGenreSelection.contains(genre.key);
        return _buildSelectableRow(
          title: genre.label,
          selected: selected,
          onTap: () => _toggleGenre(genre.key),
        );
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

  Widget _buildSelectableRow({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final compact = isCompactListWidth(context);
    return MergeSemantics(
      child: ObsidianHoverRow(
        isActive: selected,
        onTap: onTap,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        child: Row(
          children: [
            LucideCheckbox(
              value: selected,
              onChanged: (_) => onTap(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: ObsidianPalette.textMuted),
              activeColor: ObsidianPalette.gold,
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: compact ? 14.5 : null,
                  letterSpacing: compact ? 0.2 : 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineMessage(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
        ),
      ),
    );
  }

  void _handleArtistScroll() {
    _maybeLoadMoreArtists();
  }

  void _maybeLoadMoreArtists() {
    final controller = _controller;
    if (!mounted || controller == null || !_scrollController.hasClients) {
      return;
    }
    if (_view != _CustomShuffleView.artists) {
      return;
    }
    if (!_showingServerTarget) {
      return;
    }
    if (_artistSearchController.text.trim().isNotEmpty) {
      return;
    }
    if (controller.artistsLoading || !controller.hasMoreArtists) {
      return;
    }
    if (_scrollController.position.extentAfter > 640) {
      return;
    }
    unawaited(controller.loadMoreArtists());
  }
}

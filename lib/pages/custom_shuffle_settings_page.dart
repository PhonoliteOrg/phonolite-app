import 'dart:async';

import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/hover_row.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/tech_button.dart';

class CustomShuffleSettingsPage extends StatefulWidget {
  const CustomShuffleSettingsPage({super.key});

  @override
  State<CustomShuffleSettingsPage> createState() =>
      _CustomShuffleSettingsPageState();
}

enum _CustomShuffleView { artists, genres }

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
    if (_controller!.authState.isAuthorized && _controller!.artists.isEmpty) {
      unawaited(_controller!.loadArtists());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreArtists());
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

  void _toggleArtist(String artistId) {
    setState(() {
      if (_selectedArtistIds.contains(artistId)) {
        _selectedArtistIds.remove(artistId);
      } else {
        _selectedArtistIds.add(artistId);
      }
    });
    _scheduleSave();
  }

  void _selectAllArtists(List<Artist> artists) {
    setState(() {
      _selectedArtistIds
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
    await controller.loadAllArtists();
    if (!mounted) {
      return;
    }
    _selectAllArtists(controller.artists);
  }

  void _clearArtists() {
    setState(() => _selectedArtistIds.clear());
    _scheduleSave();
  }

  void _toggleGenre(String genreKey) {
    setState(() {
      if (_selectedGenres.contains(genreKey)) {
        _selectedGenres.remove(genreKey);
      } else {
        _selectedGenres.add(genreKey);
      }
    });
    _scheduleSave();
  }

  void _selectAllGenres(List<_GenreOption> genres) {
    setState(() {
      _selectedGenres
        ..clear()
        ..addAll(genres.map((genre) => genre.key));
    });
    _scheduleSave();
  }

  void _clearGenres() {
    setState(() => _selectedGenres.clear());
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
    _saveChain = _saveChain.then(
      (_) => controller.updateCustomShuffleSettings(
        artistIds: artistIds,
        genres: genres,
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
    for (final selected in _selectedGenres) {
      if (selected.trim().isEmpty) {
        continue;
      }
      labels.putIfAbsent(selected, () => selected);
    }
    final options = labels.entries
        .map((entry) => _GenreOption(key: entry.key, label: entry.value))
        .toList();
    options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
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
    final canLoadArtists = controller.authState.isAuthorized;

    return StreamBuilder<List<Artist>>(
      stream: controller.artistsStream,
      initialData: controller.artists,
      builder: (context, snapshot) {
        final artists = snapshot.data ?? <Artist>[];
        final filteredArtists = _filterArtists(artists);
        final genreOptions = _buildGenreOptions(artists);
        final filteredGenres = _filterGenres(genreOptions);
        return StreamBuilder<bool>(
          stream: controller.artistsLoadingStream,
          initialData: controller.artistsLoading,
          builder: (context, loadingSnapshot) {
            final isLoading = loadingSnapshot.data ?? false;
            final showingArtists = _view == _CustomShuffleView.artists;
            final theme = Theme.of(context);
            if (showingArtists &&
                artists.isNotEmpty &&
                controller.hasMoreArtists &&
                !isLoading &&
                _artistSearchController.text.trim().isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _maybeLoadMoreArtists(),
              );
            }
            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                CommandLinkButton(
                  label: 'Back to settings',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 12),
                const ObsidianSectionHeader(
                  title: 'Custom Shuffle',
                  subtitle: 'Pick artists and genres used for library shuffles.',
                ),
                const SizedBox(height: 20),
                _buildViewToggle(),
                const SizedBox(height: 16),
                if (showingArtists) ...[
                  Text(
                    'Artists',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ObsidianPalette.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ObsidianTextField(
                    controller: _artistSearchController,
                    hintText: 'Search artists',
                    prefixIcon: const Icon(Icons.search_rounded),
                    height: 52,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.hasMoreArtists
                              ? 'Selected ${_selectedArtistIds.length} of loaded ${artists.length}'
                              : 'Selected ${_selectedArtistIds.length} of ${artists.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ObsidianPalette.textMuted,
                          ),
                        ),
                      ),
                      TechButton(
                        label: 'Select all',
                        density: TechButtonDensity.compact,
                        onTap: artists.isEmpty && !controller.hasMoreArtists
                            ? null
                            : _selectAllAvailableArtists,
                      ),
                      const SizedBox(width: 8),
                      TechButton(
                        label: 'Clear',
                        density: TechButtonDensity.compact,
                        onTap: _selectedArtistIds.isEmpty ? null : _clearArtists,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildArtistList(
                    canLoadArtists: canLoadArtists,
                    artists: filteredArtists,
                    fullCount: artists.length,
                    isLoading: isLoading,
                    hasMoreArtists: controller.hasMoreArtists,
                  ),
                ] else ...[
                  Text(
                    'Genres',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ObsidianPalette.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ObsidianTextField(
                    controller: _genreSearchController,
                    hintText: 'Search genres',
                    prefixIcon: const Icon(Icons.search_rounded),
                    height: 52,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selected ${_selectedGenres.length} of ${genreOptions.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ObsidianPalette.textMuted,
                          ),
                        ),
                      ),
                      TechButton(
                        label: 'Select all',
                        density: TechButtonDensity.compact,
                        onTap: genreOptions.isEmpty
                            ? null
                            : () => _selectAllGenres(genreOptions),
                      ),
                      const SizedBox(width: 8),
                      TechButton(
                        label: 'Clear',
                        density: TechButtonDensity.compact,
                        onTap: _selectedGenres.isEmpty ? null : _clearGenres,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildGenreList(
                    canLoadArtists: canLoadArtists,
                    genres: filteredGenres,
                    fullCount: genreOptions.length,
                    isLoading: isLoading,
                    hasMoreArtists: controller.hasMoreArtists,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildViewToggle() {
    final showingArtists = _view == _CustomShuffleView.artists;
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor.withOpacity(0.35);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleOption(
              label: 'Artists',
              icon: Icons.people_alt_rounded,
              isActive: showingArtists,
              onTap: () => setState(() => _view = _CustomShuffleView.artists),
              border: Border(
                right: BorderSide(color: borderColor),
              ),
            ),
          ),
          Expanded(
            child: _buildToggleOption(
              label: 'Genres',
              icon: Icons.local_offer_rounded,
              isActive: !showingArtists,
              onTap: () {
                setState(() => _view = _CustomShuffleView.genres);
                final controller = _controller;
                if (controller != null && controller.hasMoreArtists) {
                  unawaited(controller.loadAllArtists());
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Border? border,
  }) {
    final activeColor = ObsidianPalette.gold;
    final textColor = isActive ? activeColor : ObsidianPalette.textMuted;
    final fill = isActive
        ? ObsidianPalette.gold.withOpacity(0.12)
        : Colors.transparent;

    return Material(
      color: fill,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(border: border),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: textColor,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (fullCount == 0) {
      return _buildInlineMessage('No artists available.');
    }
    if (artists.isEmpty) {
      if (isLoading || hasMoreArtists) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _buildInlineMessage('No artists match your search.');
    }

    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: artists.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: ObsidianPalette.border.withOpacity(0.35),
          ),
          itemBuilder: (context, index) {
            final artist = artists[index];
            final selected = _selectedArtistIds.contains(artist.id);
            final subtitle = artist.genres.isEmpty
                ? null
                : artist.genres.join(', ');
            return ObsidianHoverRow(
              isActive: selected,
              onTap: () => _toggleArtist(artist.id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: ObsidianPalette.textMuted,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? ObsidianPalette.gold
                        : ObsidianPalette.textMuted,
                  ),
                ],
              ),
            );
          },
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (fullCount == 0) {
      return _buildInlineMessage('No genres available.');
    }
    if (genres.isEmpty) {
      return _buildInlineMessage('No genres match your search.');
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: genres.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: ObsidianPalette.border.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final genre = genres[index];
        final selected = _selectedGenres.contains(genre.key);
        return ObsidianHoverRow(
          isActive: selected,
          onTap: () => _toggleGenre(genre.key),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  genre.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? ObsidianPalette.gold
                    : ObsidianPalette.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: ObsidianPalette.textMuted),
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

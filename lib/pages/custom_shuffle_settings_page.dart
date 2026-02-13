import 'package:flutter/material.dart';

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

class _CustomShuffleSettingsPageState extends State<CustomShuffleSettingsPage> {
  final TextEditingController _genreController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedArtistIds = <String>{};
  bool _initialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    final controller = AppScope.of(context);
    final settings = controller.customShuffleSettings;
    _selectedArtistIds.addAll(settings.artistIds);
    _genreController.text = settings.genres.join(', ');
    if (controller.authState.isAuthorized && controller.artists.isEmpty) {
      controller.loadArtists();
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _genreController.dispose();
    _searchController.dispose();
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
  }

  void _selectAllArtists(List<Artist> artists) {
    setState(() {
      _selectedArtistIds
        ..clear()
        ..addAll(artists.map((artist) => artist.id));
    });
  }

  void _clearArtists() {
    setState(() => _selectedArtistIds.clear());
  }

  List<String> _parseGenres(String raw) {
    final parts = raw.split(RegExp(r'[,\n]'));
    final seen = <String>{};
    final genres = <String>[];
    for (final part in parts) {
      var value = part.trim();
      if (value.isEmpty) {
        continue;
      }
      value = value.toLowerCase();
      if (seen.add(value)) {
        genres.add(value);
      }
    }
    return genres;
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final controller = AppScope.of(context);
    await controller.updateCustomShuffleSettings(
      artistIds: _selectedArtistIds.toList(),
      genres: _parseGenres(_genreController.text),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Custom shuffle saved')),
    );
  }

  List<Artist> _filterArtists(List<Artist> artists) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return artists;
    }
    return artists
        .where((artist) => artist.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final theme = Theme.of(context);
    final canLoadArtists = controller.authState.isAuthorized;

    return StreamBuilder<List<Artist>>(
      stream: controller.artistsStream,
      initialData: controller.artists,
      builder: (context, snapshot) {
        final artists = snapshot.data ?? <Artist>[];
        final filtered = _filterArtists(artists);
        return StreamBuilder<bool>(
          stream: controller.artistsLoadingStream,
          initialData: controller.artistsLoading,
          builder: (context, loadingSnapshot) {
            final isLoading = loadingSnapshot.data ?? false;
            return ListView(
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
                Text(
                  'Artists',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                ObsidianTextField(
                  controller: _searchController,
                  hintText: 'Search artists',
                  prefixIcon: const Icon(Icons.search_rounded),
                  height: 52,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected ${_selectedArtistIds.length} of ${artists.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ObsidianPalette.textMuted,
                        ),
                      ),
                    ),
                    TechButton(
                      label: 'Select all',
                      density: TechButtonDensity.compact,
                      onTap:
                          artists.isEmpty ? null : () => _selectAllArtists(artists),
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
                GlassPanel(
                  cut: 18,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: 360,
                    child: _buildArtistList(
                      canLoadArtists: canLoadArtists,
                      artists: filtered,
                      fullCount: artists.length,
                      isLoading: isLoading,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Genres',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                ObsidianTextField(
                  controller: _genreController,
                  hintText: 'Comma-separated genres (e.g. rock, jazz, synthwave)',
                  height: 52,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TechButton(
                      label: _saving ? 'Saving...' : 'Save',
                      icon: Icons.save_rounded,
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildArtistList({
    required bool canLoadArtists,
    required List<Artist> artists,
    required int fullCount,
    required bool isLoading,
  }) {
    if (!canLoadArtists) {
      return const Center(
        child: Text('Connect to a server to load artists.'),
      );
    }
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (fullCount == 0) {
      return const Center(
        child: Text('No artists available.'),
      );
    }
    if (artists.isEmpty) {
      return const Center(
        child: Text('No artists match your search.'),
      );
    }

    return ListView.separated(
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ObsidianPalette.textMuted,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_rounded : Icons.circle_outlined,
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
}

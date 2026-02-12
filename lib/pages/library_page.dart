import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/artist_card.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/inputs/search_hud.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layout/search_results_sliver.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _searchController;
  bool _artistsImagesReady = false;
  String _artistsImageKey = '';
  int _artistsImageLoadId = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (controller.artists.isEmpty) {
      controller.loadArtists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);

    return Container(
      color: bgDark,
      child: Stack(
        children: [
          const SizedBox.shrink(),
          StreamBuilder<List<SearchResult>>(
            stream: controller.searchStream,
            initialData: controller.searchResults,
            builder: (context, searchSnapshot) {
              final results = searchSnapshot.data ?? [];
              return StreamBuilder<bool>(
                stream: controller.artistsLoadingStream,
                initialData: controller.artistsLoading,
                builder: (context, loadingSnapshot) {
                  final isLoading = loadingSnapshot.data ?? false;
                  return StreamBuilder<bool>(
                    stream: controller.searchLoadingStream,
                    initialData: controller.searchLoading,
                    builder: (context, searchLoadingSnapshot) {
                      final isSearchLoading =
                          searchLoadingSnapshot.data ?? false;
                      return StreamBuilder<List<Artist>>(
                        stream: controller.artistsStream,
                        initialData: controller.artists,
                        builder: (context, artistSnapshot) {
                          final artists = artistSnapshot.data ?? [];
                          final query = _searchController.text.trim();
                          _ensureArtistsImagesReady(
                              context, artists, authHeadersMap);
                          final showLoading = isLoading ||
                              (!_artistsImagesReady && artists.isNotEmpty);
                          return CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 24, 20, 12),
                                sliver: SliverToBoxAdapter(
                                  child:
                                      LibraryHeader(moduleCount: artists.length),
                                ),
                              ),
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                sliver: SliverToBoxAdapter(
                                  child: SearchHud(
                                    controller: _searchController,
                                    onSubmit: () => _runSearch(controller),
                                    onChanged: () => _queueSearch(controller),
                                    onClear: () => _clearSearch(controller),
                                  ),
                                ),
                              ),
                              if (query.isNotEmpty && isSearchLoading)
                                loadingSliver()
                              else if (query.isNotEmpty && results.isNotEmpty)
                                SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  sliver: SearchResultsSliver(
                                    results: results,
                                    onSelect: (result) =>
                                        _handleSearchSelect(controller, result),
                                  ),
                                )
                              else if (query.isNotEmpty && results.isEmpty)
                                SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 24, 20, 0),
                                  sliver: SliverToBoxAdapter(
                                    child: Text(
                                      'No Results',
                                      style: GoogleFonts.rajdhani(
                                        color: Colors.white54,
                                        fontSize: 14,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                              else if (artists.isEmpty && showLoading)
                                loadingSliver()
                              else if (artists.isEmpty)
                                const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: EmptyStateText(
                                    title: 'No artists',
                                    message:
                                        'Add music to your library to get started.',
                                  ),
                                )
                              else if (showLoading)
                                loadingSliver()
                              else
                                SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 32),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 240,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: 0.82,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final artist = artists[index];
                                        return ArtistCard(
                                          artist: artist,
                                          coverUrl: controller.connection
                                              .buildArtistCoverUrl(artist.id,
                                                  kind: 'logo'),
                                          headers: authHeadersMap,
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ArtistDetailScreen(
                                                  artist: artist,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                      childCount: artists.length,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _runSearch(AppController controller) {
    final query = _searchController.text.trim();
    controller.search(query, filter: 'all');
  }

  void _queueSearch(AppController controller) {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      controller.search('', filter: 'all');
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      controller.search(query, filter: 'all');
    });
  }

  void _clearSearch(AppController controller) {
    _searchController.clear();
    _searchDebounce?.cancel();
    controller.search('', filter: 'all');
  }

  Future<void> _handleSearchSelect(
    AppController controller,
    SearchResult result,
  ) async {
    try {
      switch (result.kind) {
        case 'artist':
          final artist = await controller.connection.fetchArtistById(result.id);
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          break;
        case 'album':
          final album = await controller.connection.fetchAlbumById(result.id);
          final artist =
              await controller.connection.fetchArtistById(album.artistId);
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          final navigator = Navigator.of(context);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(
                album: album,
                artistName: album.artist,
              ),
            ),
          );
          break;
        case 'track':
          final track = await controller.connection.fetchTrackById(result.id);
          final albumId = track.albumId;
          if (albumId == null || albumId.isEmpty) {
            return;
          }
          final album = await controller.connection.fetchAlbumById(albumId);
          final artist =
              await controller.connection.fetchArtistById(album.artistId);
          await controller.loadTracks(album.id);
          await controller.queueAlbum(album.id, startTrackId: track.id);
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          final navigator = Navigator.of(context);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(
                album: album,
                artistName: album.artist.isNotEmpty ? album.artist : track.artist,
              ),
            ),
          );
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void _ensureArtistsImagesReady(
    BuildContext context,
    List<Artist> artists,
    Map<String, String> headers,
  ) {
    final nextKey = artists.map((artist) => artist.id).join('|');
    if (nextKey == _artistsImageKey) {
      return;
    }
    _artistsImageKey = nextKey;
    _artistsImageLoadId++;
    final loadId = _artistsImageLoadId;
    _artistsImagesReady = false;
    if (artists.isEmpty) {
      _artistsImagesReady = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final urls = artists
          .map((artist) => AppScope.of(context)
              .connection
              .buildArtistCoverUrl(artist.id, kind: 'logo'))
          .toList();
      await precacheImages(context, urls, headers: headers);
      if (!mounted || loadId != _artistsImageLoadId) {
        return;
      }
      setState(() => _artistsImagesReady = true);
    });
  }
}

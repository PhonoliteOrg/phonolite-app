import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/album_card.dart';
import '../widgets/display/artist_hero.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/navigation/command_link_button.dart';
import 'album_detail_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final Artist artist;

  @override
  State<ArtistDetailScreen> createState() => ArtistDetailScreenState();
}

class ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _loaded = false;
  late Artist _artist;
  bool _albumsImagesReady = false;
  String _albumsImageKey = '';
  int _albumsImageLoadId = 0;
  bool _artistHeroReady = false;
  String _artistHeroKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final controller = AppScope.of(context);
    _artist = widget.artist;
    controller.loadAlbums(widget.artist.id);
    _refreshArtist(controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = controller.connection
        .buildArtistCoverUrl(_artist.id, kind: 'logo');
    final bannerUrl = controller.connection
        .buildArtistCoverUrl(_artist.id, kind: 'banner');
    _ensureArtistHeroReady(context, coverUrl, bannerUrl, authHeadersMap);

    return Scaffold(
      backgroundColor: bgDark,
      body: Stack(
        children: [
          const SizedBox.shrink(),
          SafeArea(
            child: StreamBuilder<bool>(
              stream: controller.albumsLoadingStream,
              initialData: controller.albumsLoading,
              builder: (context, loadingSnapshot) {
                final isLoading = loadingSnapshot.data ?? false;
                return StreamBuilder<List<Album>>(
                  stream: controller.albumsStream,
                  initialData: controller.albums,
                  builder: (context, snapshot) {
                    final albums = snapshot.data ?? [];
                    _ensureAlbumImagesReady(context, albums, authHeadersMap);
                    final ready = _artistHeroReady &&
                        !isLoading &&
                        (albums.isEmpty || _albumsImagesReady);
                    if (!ready) {
                      return fullPageSpinner();
                    }
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          sliver: SliverToBoxAdapter(
                            child: CommandLinkButton(
                              label: 'Back to library',
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          sliver: SliverToBoxAdapter(
                            child: ArtistHero(
                              artist: _artist,
                              coverUrl: coverUrl,
                              bannerUrl: bannerUrl,
                              headers: authHeadersMap,
                            ),
                          ),
                        ),
                        if (albums.isEmpty)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                            sliver: SliverToBoxAdapter(
                              child: EmptyState(
                                title: 'No albums',
                                message: 'This artist has no albums yet.',
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
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
                                  final album = albums[index];
                                  return AlbumCard(
                                    album: album,
                                    coverUrl: controller.connection
                                        .buildAlbumCoverUrl(album.id),
                                    headers: authHeadersMap,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AlbumDetailScreen(
                                            album: album,
                                            artistName: _artist.name,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                childCount: albums.length,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshArtist(AppController controller) async {
    try {
      final updated =
          await controller.connection.fetchArtistById(widget.artist.id);
      if (!mounted) {
        return;
      }
      setState(() => _artist = updated);
    } catch (_) {}
  }

  void _ensureArtistHeroReady(
    BuildContext context,
    String coverUrl,
    String bannerUrl,
    Map<String, String> headers,
  ) {
    final nextKey = '$coverUrl|$bannerUrl';
    if (nextKey == _artistHeroKey) {
      return;
    }
    _artistHeroKey = nextKey;
    _artistHeroReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await precacheImages(context, [coverUrl, bannerUrl], headers: headers);
      if (!mounted || _artistHeroKey != nextKey) {
        return;
      }
      setState(() => _artistHeroReady = true);
    });
  }

  void _ensureAlbumImagesReady(
    BuildContext context,
    List<Album> albums,
    Map<String, String> headers,
  ) {
    final nextKey = albums.map((album) => album.id).join('|');
    if (nextKey == _albumsImageKey) {
      return;
    }
    _albumsImageKey = nextKey;
    _albumsImageLoadId++;
    final loadId = _albumsImageLoadId;
    _albumsImagesReady = false;
    if (albums.isEmpty) {
      _albumsImagesReady = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final urls = albums
          .map((album) =>
              AppScope.of(context).connection.buildAlbumCoverUrl(album.id))
          .toList();
      await precacheImages(context, urls, headers: headers);
      if (!mounted || loadId != _albumsImageLoadId) {
        return;
      }
      setState(() => _albumsImagesReady = true);
    });
  }
}

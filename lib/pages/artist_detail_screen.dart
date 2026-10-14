import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';

import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_download_manager.dart';
import '../entities/offline_models.dart';
import '../widgets/display/album_card.dart';
import '../widgets/display/album_row_tile.dart';
import '../widgets/display/artist_hero.dart';
import '../widgets/display/artist_release_sections.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/layout/safe_sliver_grid.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/playback_content_inset.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/navigation/detail_action_header.dart';
import '../widgets/ui/collection_view_toggle_button.dart';
import '../widgets/ui/responsive_breakpoints.dart';
import '../widgets/ui/tech_button.dart';
import 'album_detail_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final Artist artist;

  static String routeNameFor(String artistId) =>
      '/library/server/artist/$artistId';

  @override
  State<ArtistDetailScreen> createState() => ArtistDetailScreenState();
}

class ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _loaded = false;
  bool _albumSelectionMode = false;
  late Artist _artist;
  StreamSubscription<Artist>? _artistSubscription;
  final Set<String> _selectedAlbumIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final controller = AppScope.of(context);
    _artist = widget.artist;
    controller.loadArtistReleases(widget.artist.id);
    _refreshArtist(controller);
    _artistSubscription = controller.watchArtist(widget.artist.id).listen((
      updated,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _artist = updated);
    });
  }

  @override
  void dispose() {
    _artistSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = _artist.logoRef == null || _artist.logoRef!.isEmpty
        ? null
        : controller.connection.buildArtistCoverUrl(
            _artist.id,
            kind: 'logo',
            ref: _artist.logoRef,
          );
    final bannerUrl = _artist.bannerRef == null || _artist.bannerRef!.isEmpty
        ? null
        : controller.connection.buildArtistCoverUrl(
            _artist.id,
            kind: 'banner',
            ref: _artist.bannerRef,
          );
    final compactHeaderActions = isCompactListWidth(context);

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: controller.albumsLoadingStream,
          initialData: controller.albumsLoading,
          builder: (context, loadingSnapshot) {
            final isLoading = loadingSnapshot.data ?? false;
            return StreamBuilder<ArtistReleases>(
              stream: controller.artistReleasesStream,
              initialData: controller.artistReleases,
              builder: (context, snapshot) {
                final releases = snapshot.data ?? const ArtistReleases();
                final albums = releases.albums;
                final headlineAlbums = releases.headlineAlbums;
                return StreamBuilder<bool>(
                  stream: controller.collectionListModeStream,
                  initialData: controller.collectionListMode,
                  builder: (context, viewModeSnapshot) {
                    final showCollectionList =
                        viewModeSnapshot.data ?? controller.collectionListMode;
                    return StreamBuilder<OfflineDownloadSnapshot>(
                      stream: controller.offlineDownloadSnapshotStream,
                      initialData: controller.offlineDownloadSnapshot,
                      builder: (context, _) {
                        final downloadSummary =
                            _ArtistDownloadSummary.forArtist(
                              controller,
                              _artist,
                              headlineAlbums,
                            );
                        final removableAlbumIds = _removableAlbumIds(
                          controller,
                          headlineAlbums,
                        );
                        final removingAlbumIds = _removingAlbumIds(
                          controller,
                          headlineAlbums,
                        );
                        final selectedAlbums = _selectedAlbums(
                          headlineAlbums,
                          removableAlbumIds,
                        );
                        return CustomScrollView(
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                16,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: DetailActionHeader(
                                  backLabel: 'Back to library',
                                  onBack: () => Navigator.of(context).pop(),
                                  actions: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: _albumSelectionMode
                                        ? [
                                            DownloadSelectionToolbar(
                                              selectedCount:
                                                  selectedAlbums.length,
                                              totalCount:
                                                  removableAlbumIds.length,
                                              onCancel: _clearAlbumSelection,
                                              onSelectAll: () =>
                                                  _selectAllAlbums(
                                                    removableAlbumIds,
                                                  ),
                                              onDeselectAll: _deselectAllAlbums,
                                              onRemove: selectedAlbums.isEmpty
                                                  ? null
                                                  : () =>
                                                        _removeSelectedAlbumDownloads(
                                                          controller,
                                                          selectedAlbums,
                                                        ),
                                            ),
                                          ]
                                        : [
                                            TechButton(
                                              label: downloadSummary.label,
                                              icon: downloadSummary.icon,
                                              iconOnly: compactHeaderActions,
                                              tooltip: downloadSummary.label,
                                              chrome:
                                                  TechButtonChrome.borderless,
                                              onTap:
                                                  !isLoading &&
                                                      downloadSummary.canStart
                                                  ? () =>
                                                        _confirmDownloadArtist(
                                                          controller,
                                                          headlineAlbums,
                                                          downloadSummary,
                                                        )
                                                  : null,
                                            ),
                                            CollectionViewToggleButton(
                                              isListView: showCollectionList,
                                              onPressed: controller
                                                  .toggleCollectionListMode,
                                            ),
                                          ],
                                  ),
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
                            if (!isLoading && albums.isNotEmpty)
                              ArtistReleaseHeading(
                                title: 'Albums',
                                count: albums.length,
                              ),
                            if (isLoading && albums.isEmpty)
                              loadingSliver()
                            else if (albums.isEmpty &&
                                releases.collabAlbums.isEmpty)
                              const SliverPadding(
                                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                                sliver: SliverToBoxAdapter(
                                  child: EmptyStateText(
                                    title: 'Artist has no albums',
                                  ),
                                ),
                              )
                            else if (albums.isNotEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  32,
                                ),
                                sliver: showCollectionList
                                    ? SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            if (index.isOdd) {
                                              return const Divider(height: 1);
                                            }
                                            final album = albums[index ~/ 2];
                                            final isDeleting = removingAlbumIds
                                                .contains(
                                                  _albumSelectionKey(album),
                                                );
                                            return AlbumRowTile(
                                              album: album,
                                              coverUrl: _albumCoverUrl(
                                                controller,
                                                album,
                                              ),
                                              headers: authHeadersMap,
                                              onTap: () =>
                                                  _openAlbumDetail(album),
                                              selectionMode:
                                                  _albumSelectionMode,
                                              selectable:
                                                  !isDeleting &&
                                                  removableAlbumIds.contains(
                                                    _albumSelectionKey(album),
                                                  ),
                                              isDeleting: isDeleting,
                                              selected: _selectedAlbumIds
                                                  .contains(
                                                    _albumSelectionKey(album),
                                                  ),
                                              onSelectionToggle: () =>
                                                  _toggleAlbumSelection(album),
                                            );
                                          },
                                          childCount: albums.isEmpty
                                              ? 0
                                              : albums.length * 2 - 1,
                                        ),
                                      )
                                    : SafeSliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 240,
                                              mainAxisSpacing: 16,
                                              crossAxisSpacing: 16,
                                              childAspectRatio: 0.82,
                                            ),
                                        delegate: SliverChildBuilderDelegate((
                                          context,
                                          index,
                                        ) {
                                          final album = albums[index];
                                          final isDeleting = removingAlbumIds
                                              .contains(
                                                _albumSelectionKey(album),
                                              );
                                          return AlbumCard(
                                            album: album,
                                            coverUrl: _albumCoverUrl(
                                              controller,
                                              album,
                                            ),
                                            headers: authHeadersMap,
                                            onTap: () =>
                                                _openAlbumDetail(album),
                                            selectionMode: _albumSelectionMode,
                                            selectable:
                                                !isDeleting &&
                                                removableAlbumIds.contains(
                                                  _albumSelectionKey(album),
                                                ),
                                            isDeleting: isDeleting,
                                            selected: _selectedAlbumIds
                                                .contains(
                                                  _albumSelectionKey(album),
                                                ),
                                            onSelectionToggle: () =>
                                                _toggleAlbumSelection(album),
                                          );
                                        }, childCount: albums.length),
                                      ),
                              ),
                            if (!isLoading && releases.collabAlbums.isNotEmpty)
                              ArtistContributionSliver(
                                title: 'Collab albums',
                                entries: releases.collabAlbums,
                                isListView: showCollectionList,
                                coverFor: (album) =>
                                    _albumCoverUrl(controller, album),
                                headers: authHeadersMap,
                                onOpen: _openAlbumDetail,
                                selectionMode: _albumSelectionMode,
                                selected: (entry) => _selectedAlbumIds.contains(
                                  _albumSelectionKey(entry.album),
                                ),
                                selectable: (entry) =>
                                    entry.isAlbumArtist &&
                                    !removingAlbumIds.contains(
                                      _albumSelectionKey(entry.album),
                                    ) &&
                                    removableAlbumIds.contains(
                                      _albumSelectionKey(entry.album),
                                    ),
                                isDeleting: (entry) => removingAlbumIds
                                    .contains(_albumSelectionKey(entry.album)),
                                onSelectionToggle: (entry) =>
                                    _toggleAlbumSelection(entry.album),
                              ),
                            if (!isLoading && releases.appearsOn.isNotEmpty)
                              ArtistContributionSliver(
                                title: 'Appears on',
                                entries: releases.appearsOn,
                                isListView: showCollectionList,
                                coverFor: (album) =>
                                    _albumCoverUrl(controller, album),
                                headers: authHeadersMap,
                                onOpen: _openAlbumDetail,
                              ),
                            if (!isLoading && releases.otherCredits.isNotEmpty)
                              ArtistContributionSliver(
                                title: 'Other credits',
                                entries: releases.otherCredits,
                                isListView: showCollectionList,
                                coverFor: (album) =>
                                    _albumCoverUrl(controller, album),
                                headers: authHeadersMap,
                                onOpen: _openAlbumDetail,
                              ),
                            if (isLoading && albums.isNotEmpty)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SliverPlaybackInset(),
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
      ),
    );
  }

  Future<void> _confirmDownloadArtist(
    AppController controller,
    List<Album> albums,
    _ArtistDownloadSummary downloadSummary,
  ) async {
    final trackCount = downloadSummary.total;
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Download artist',
      message: trackCount > 0
          ? 'Queue downloads for ${_artist.name} ($trackCount $trackLabel)? This may use significant storage.'
          : 'Queue downloads for every album by ${_artist.name}? This may use significant storage.',
      confirmLabel: 'Download',
      confirmVariant: TechButtonVariant.standard,
      actionChrome: TechButtonChrome.borderless,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await controller.downloadArtist(_artist, albums);
  }

  Future<void> _removeSelectedAlbumDownloads(
    AppController controller,
    List<Album> albums,
  ) async {
    final downloads = _downloadsForAlbums(controller, albums);
    if (downloads.isEmpty) {
      return;
    }
    final label = albums.length == 1
        ? albums.single.title
        : '${albums.length} albums';
    final confirmed = await confirmRemoveDownloadedDownloads(
      context,
      downloads,
      label: label,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await controller.removeOfflineDownloads(
      downloads,
      label: label,
      scope: OfflineDeletionScope.album(
        id: albums.length == 1 ? albums.single.id : null,
        label: label,
      ),
    );
    if (mounted) {
      _clearAlbumSelection();
    }
  }

  Set<String> _removableAlbumIds(AppController controller, List<Album> albums) {
    return <String>{
      for (final album in albums)
        if (_downloadsForAlbum(controller, album).isNotEmpty)
          _albumSelectionKey(album),
    };
  }

  Set<String> _removingAlbumIds(AppController controller, List<Album> albums) {
    return <String>{
      for (final album in albums)
        if (_albumHasRemovingDownloads(controller, album))
          _albumSelectionKey(album),
    };
  }

  List<Album> _selectedAlbums(List<Album> albums, Set<String> removableIds) {
    return albums
        .where((album) {
          final key = _albumSelectionKey(album);
          return removableIds.contains(key) && _selectedAlbumIds.contains(key);
        })
        .toList(growable: false);
  }

  List<OfflineTrackDownload> _downloadsForAlbums(
    AppController controller,
    List<Album> albums,
  ) {
    final downloadsByKey = <String, OfflineTrackDownload>{};
    for (final album in albums) {
      for (final download in _downloadsForAlbum(controller, album)) {
        downloadsByKey[_downloadSelectionKey(download)] = download;
      }
    }
    return downloadsByKey.values.toList(growable: false);
  }

  List<OfflineTrackDownload> _downloadsForAlbum(
    AppController controller,
    Album album,
  ) {
    return controller.offlineDownloads
        .where(
          (download) =>
              controller.availableOfflineDownloadForTrack(download.track.id) !=
                  null &&
              _downloadBelongsToAlbum(download, album),
        )
        .toList(growable: false);
  }

  bool _albumHasRemovingDownloads(AppController controller, Album album) {
    return controller.offlineDownloads.any(
      (download) =>
          download.status == OfflineDownloadStatus.removing &&
          _downloadBelongsToAlbum(download, album),
    );
  }

  bool _downloadBelongsToAlbum(OfflineTrackDownload download, Album album) {
    final track = download.track;
    final trackAlbumId = track.albumId?.trim();
    if (trackAlbumId != null && trackAlbumId.isNotEmpty) {
      return trackAlbumId == album.id;
    }

    final trackAlbum = _normalizedAlbumSelectionValue(track.album);
    final albumTitle = _normalizedAlbumSelectionValue(album.title);
    if (trackAlbum.isEmpty || trackAlbum != albumTitle) {
      return false;
    }

    final trackArtistId = track.artistId?.trim();
    if (trackArtistId != null && trackArtistId.isNotEmpty) {
      return trackArtistId == album.artistId || trackArtistId == _artist.id;
    }

    final trackArtist = _normalizedAlbumSelectionValue(track.artist);
    if (trackArtist.isEmpty) {
      return true;
    }
    final albumArtist = _normalizedAlbumSelectionValue(
      album.artist.isEmpty ? _artist.name : album.artist,
    );
    final artistName = _normalizedAlbumSelectionValue(_artist.name);
    return trackArtist == albumArtist || trackArtist == artistName;
  }

  void _toggleAlbumSelection(Album album) {
    final key = _albumSelectionKey(album);
    setState(() {
      _albumSelectionMode = true;
      if (!_selectedAlbumIds.remove(key)) {
        _selectedAlbumIds.add(key);
      }
    });
  }

  void _selectAllAlbums(Set<String> albumIds) {
    setState(() {
      _albumSelectionMode = true;
      _selectedAlbumIds
        ..clear()
        ..addAll(albumIds);
    });
  }

  void _deselectAllAlbums() {
    setState(() {
      _albumSelectionMode = true;
      _selectedAlbumIds.clear();
    });
  }

  void _clearAlbumSelection() {
    setState(() {
      _albumSelectionMode = false;
      _selectedAlbumIds.clear();
    });
  }

  Future<void> _refreshArtist(AppController controller) async {
    try {
      final updated = await controller.connection.fetchArtistById(
        widget.artist.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => _artist = updated);
    } catch (_) {}
  }

  String _albumCoverUrl(AppController controller, Album album) {
    return controller.connection.buildAlbumCoverUrl(album.id);
  }

  void _openAlbumDetail(Album album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: AlbumDetailScreen.routeNameFor(album.id)),
        builder: (_) => AlbumDetailScreen(
          album: album,
          artistName: album.artist.isEmpty ? _artist.name : album.artist,
        ),
      ),
    );
  }

  String _albumSelectionKey(Album album) => album.id;

  String _downloadSelectionKey(OfflineTrackDownload download) {
    final trackId = download.track.serverTrackId ?? download.track.id;
    return '${download.serverBaseUrl}\n$trackId\n${download.localTrackId ?? ''}';
  }

  String _normalizedAlbumSelectionValue(String value) {
    return value.trim().toLowerCase();
  }
}

class _ArtistDownloadSummary {
  const _ArtistDownloadSummary({
    required this.total,
    required this.downloaded,
    required this.active,
    required this.failed,
    required this.hasDownloadScope,
  });

  factory _ArtistDownloadSummary.forArtist(
    AppController controller,
    Artist artist,
    List<Album> albums,
  ) {
    final albumIds = albums.map((album) => album.id).toSet();
    final albumTitles = albums
        .map((album) => album.title.trim().toLowerCase())
        .where((title) => title.isNotEmpty)
        .toSet();
    final artistName = artist.name.trim().toLowerCase();
    final downloads = <String, OfflineTrackDownload>{};
    for (final download in controller.offlineDownloads) {
      final track = download.track;
      final albumId = track.albumId;
      final trackArtist = track.artist.trim().toLowerCase();
      final trackAlbum = track.album.trim().toLowerCase();
      final belongsToArtist =
          track.artistId == artist.id ||
          (trackArtist.isNotEmpty && trackArtist == artistName) ||
          (albumId != null && albumIds.contains(albumId)) ||
          (trackAlbum.isNotEmpty &&
              albumTitles.contains(trackAlbum) &&
              (trackArtist.isEmpty || trackArtist == artistName));
      if (!belongsToArtist) {
        continue;
      }
      final key =
          download.localTrackId ??
          track.localId ??
          track.serverTrackId ??
          track.id;
      downloads[key] = download;
    }

    var downloaded = 0;
    var active = 0;
    var failed = 0;
    for (final download in downloads.values) {
      if (controller.availableOfflineDownloadForTrack(download.track.id) !=
          null) {
        downloaded++;
      } else if (download.status == OfflineDownloadStatus.queued ||
          download.status == OfflineDownloadStatus.preparing ||
          download.status == OfflineDownloadStatus.downloading ||
          download.status == OfflineDownloadStatus.validating ||
          download.status == OfflineDownloadStatus.removing) {
        active++;
      } else if (download.status == OfflineDownloadStatus.failed) {
        failed++;
      }
    }
    for (final job in controller.offlineDownloadJobs) {
      final jobLabel = job.label?.trim().toLowerCase();
      final belongsToArtist =
          job.kind == 'artist' &&
          (jobLabel == artistName || job.jobId.contains(artist.id));
      if (!belongsToArtist) {
        continue;
      }
      if (job.status == OfflineDownloadStatus.queued ||
          job.status == OfflineDownloadStatus.preparing ||
          job.status == OfflineDownloadStatus.downloading ||
          job.status == OfflineDownloadStatus.validating ||
          job.status == OfflineDownloadStatus.paused ||
          job.status == OfflineDownloadStatus.removing) {
        active += job.totalCount > 0 ? job.totalCount : 1;
      } else if (job.status == OfflineDownloadStatus.failed ||
          job.status == OfflineDownloadStatus.corrupt) {
        failed += job.failedCount > 0 ? job.failedCount : 1;
      }
    }
    final total = albums.fold<int>(0, (sum, album) => sum + album.trackCount);
    return _ArtistDownloadSummary(
      total: total,
      downloaded: downloaded,
      active: active,
      failed: failed,
      hasDownloadScope: albums.isNotEmpty,
    );
  }

  final int total;
  final int downloaded;
  final int active;
  final int failed;
  final bool hasDownloadScope;

  bool get isComplete => total > 0 && downloaded >= total;
  bool get canStart =>
      hasDownloadScope && active == 0 && (!isComplete || total == 0);

  String get label {
    if (active > 0) {
      return 'Downloading';
    }
    if (isComplete) {
      return 'Downloaded';
    }
    if (failed > 0) {
      return 'Retry Downloads';
    }
    if (downloaded > 0) {
      return 'Download Missing';
    }
    return 'Download Artist';
  }

  IconData get icon {
    if (active > 0) {
      return PhonoliteIcons.download;
    }
    if (isComplete) {
      return PhonoliteIcons.circleCheck;
    }
    if (failed > 0) {
      return PhonoliteIcons.download;
    }
    return PhonoliteIcons.download;
  }
}

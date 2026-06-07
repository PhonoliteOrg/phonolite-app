import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../widgets/display/album_hero.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/navigation/detail_action_header.dart';
import '../widgets/ui/tech_button.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.artistName,
  });

  final Album album;
  final String artistName;

  @override
  State<AlbumDetailScreen> createState() => AlbumDetailScreenState();
}

class AlbumDetailScreenState extends State<AlbumDetailScreen> {
  bool _loaded = false;
  bool _selectionMode = false;
  late Album _album;
  StreamSubscription<Album>? _albumSubscription;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final controller = AppScope.of(context);
    _album = widget.album;
    controller.loadTracks(widget.album.id);
    _albumSubscription = controller.watchAlbum(widget.album.id).listen((
      updated,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _album = updated);
    });
  }

  @override
  void dispose() {
    _albumSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = controller.connection.buildAlbumCoverUrl(_album.id);

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: controller.tracksLoadingStream,
          initialData: controller.tracksLoading,
          builder: (context, loadingSnapshot) {
            final isLoading = loadingSnapshot.data ?? false;
            return StreamBuilder<List<Track>>(
              stream: controller.tracksStream,
              initialData: controller.tracks,
              builder: (context, snapshot) {
                final tracks = snapshot.data ?? [];
                return StreamBuilder<PlaybackState>(
                  stream: controller.playbackStream,
                  initialData: controller.playbackState,
                  builder: (context, playbackSnapshot) {
                    final playback =
                        playbackSnapshot.data ?? controller.playbackState;
                    final playingId = playback.track?.id;
                    return StreamBuilder<List<OfflineTrackDownload>>(
                      stream: controller.offlineDownloadsStream,
                      initialData: controller.offlineDownloads,
                      builder: (context, _) {
                        final downloadSummary =
                            _CollectionDownloadSummary.forTracks(
                              controller,
                              tracks,
                            );
                        final removableTracks = _removableTracks(
                          controller,
                          tracks,
                        );
                        final selectedTracks = _selectedTracks(removableTracks);
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
                                  backLabel: 'Back to artist',
                                  onBack: () => Navigator.of(context).pop(),
                                  actions: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: _selectionMode
                                        ? [
                                            DownloadSelectionToolbar(
                                              selectedCount:
                                                  selectedTracks.length,
                                              totalCount:
                                                  removableTracks.length,
                                              onCancel: _clearSelection,
                                              onSelectAll: () =>
                                                  _selectAll(removableTracks),
                                              onDeselectAll: _deselectAll,
                                              onRemove: selectedTracks.isEmpty
                                                  ? null
                                                  : () =>
                                                        _removeSelectedDownloads(
                                                          controller,
                                                          selectedTracks,
                                                          _album.title,
                                                        ),
                                            ),
                                          ]
                                        : [
                                            TechButton(
                                              label: downloadSummary.label,
                                              icon: downloadSummary.icon,
                                              chrome:
                                                  TechButtonChrome.borderless,
                                              onTap:
                                                  !isLoading &&
                                                      downloadSummary.canStart
                                                  ? () => controller
                                                        .downloadAlbum(
                                                          _album,
                                                          tracks,
                                                        )
                                                  : null,
                                            ),
                                          ],
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              sliver: SliverToBoxAdapter(
                                child: AlbumHero(
                                  album: _album,
                                  coverUrl: coverUrl,
                                  headers: authHeadersMap,
                                ),
                              ),
                            ),
                            if (isLoading && tracks.isEmpty)
                              loadingSliver()
                            else if (tracks.isEmpty)
                              const SliverPadding(
                                padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                                sliver: SliverToBoxAdapter(
                                  child: EmptyState(
                                    title: 'No tracks',
                                    message:
                                        'Pick another album to see tracks.',
                                  ),
                                ),
                              ),
                            if (!isLoading && tracks.isNotEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  24,
                                ),
                                sliver: TrackSliverList(
                                  tracks: tracks,
                                  isPlayingTrack: (track) =>
                                      playback.isPlaying &&
                                      playingId == track.id,
                                  onTrackTap: (track) => controller.queueAlbum(
                                    _album.id,
                                    startTrackId: track.id,
                                  ),
                                  onTrackAddToPlaylist: (track) =>
                                      showAddToPlaylistModalForTrack(
                                        context,
                                        track,
                                        scope: ActionScope.server,
                                      ),
                                  onTrackDownload: controller.downloadTrack,
                                  onTrackLike: controller.toggleLike,
                                  selectionMode: _selectionMode,
                                  canSelectTrack: (track) =>
                                      _canRemoveTrack(controller, track),
                                  isTrackSelected: (track) => _selectedTrackIds
                                      .contains(_selectionKey(track)),
                                  onTrackSelectionToggle: (track) =>
                                      _toggleSelection(controller, track),
                                  offlineDownloadForTrack: (track) => controller
                                      .offlineDownloadForTrack(track.id),
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
      ),
    );
  }

  Future<void> _removeDownloads(
    AppController controller,
    List<Track> tracks,
    String label,
  ) async {
    if (tracks.isEmpty) {
      return;
    }
    final confirmed = await confirmRemoveDownloadedTracks(
      context,
      tracks,
      label: label,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await controller.removeDownloadedTracks(
      tracks,
      label: label,
      scope: const OfflineDeletionScope.track(),
    );
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _removeSelectedDownloads(
    AppController controller,
    List<Track> tracks,
    String label,
  ) {
    return _removeDownloads(controller, tracks, label);
  }

  List<Track> _removableTracks(AppController controller, List<Track> tracks) {
    return tracks
        .where((track) => _canRemoveTrack(controller, track))
        .toList(growable: false);
  }

  List<Track> _selectedTracks(List<Track> tracks) {
    return tracks
        .where((track) => _selectedTrackIds.contains(_selectionKey(track)))
        .toList(growable: false);
  }

  bool _canRemoveTrack(AppController controller, Track track) {
    return controller.availableOfflineDownloadForTrack(track.id) != null;
  }

  void _toggleSelection(AppController controller, Track track) {
    if (!_canRemoveTrack(controller, track)) {
      return;
    }
    final key = _selectionKey(track);
    setState(() {
      _selectionMode = true;
      if (!_selectedTrackIds.remove(key)) {
        _selectedTrackIds.add(key);
      }
    });
  }

  void _selectAll(List<Track> tracks) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds
        ..clear()
        ..addAll(tracks.map(_selectionKey));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  String _selectionKey(Track track) {
    return track.localId ?? track.serverTrackId ?? track.id;
  }
}

class _CollectionDownloadSummary {
  const _CollectionDownloadSummary({
    required this.total,
    required this.downloaded,
    required this.active,
    required this.failed,
  });

  factory _CollectionDownloadSummary.forTracks(
    AppController controller,
    List<Track> tracks,
  ) {
    var downloaded = 0;
    var active = 0;
    var failed = 0;
    for (final track in tracks) {
      final download = controller.offlineDownloadForTrack(track.id);
      if (controller.availableOfflineDownloadForTrack(track.id) != null) {
        downloaded++;
      } else if (download?.status == OfflineDownloadStatus.queued ||
          download?.status == OfflineDownloadStatus.preparing ||
          download?.status == OfflineDownloadStatus.downloading ||
          download?.status == OfflineDownloadStatus.validating ||
          download?.status == OfflineDownloadStatus.removing) {
        active++;
      } else if (download?.status == OfflineDownloadStatus.failed) {
        failed++;
      }
    }
    return _CollectionDownloadSummary(
      total: tracks.length,
      downloaded: downloaded,
      active: active,
      failed: failed,
    );
  }

  final int total;
  final int downloaded;
  final int active;
  final int failed;

  bool get isComplete => total > 0 && downloaded >= total;
  bool get canStart => total > 0 && active == 0 && !isComplete;

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
    return 'Download Album';
  }

  IconData get icon {
    if (active > 0) {
      return Icons.downloading_rounded;
    }
    if (isComplete) {
      return Icons.offline_pin_rounded;
    }
    if (failed > 0) {
      return Icons.download_for_offline_rounded;
    }
    return Icons.download_for_offline_outlined;
  }
}

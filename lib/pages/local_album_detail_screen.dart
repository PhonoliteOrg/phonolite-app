import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../entities/offline_library_views.dart';
import '../widgets/display/album_hero.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/obsidian_widgets.dart';

class LocalAlbumDetailScreen extends StatefulWidget {
  const LocalAlbumDetailScreen({super.key, required this.album});

  final OfflineAlbumGroup album;

  @override
  State<LocalAlbumDetailScreen> createState() => _LocalAlbumDetailScreenState();
}

class _LocalAlbumDetailScreenState extends State<LocalAlbumDetailScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: StreamBuilder<PlaybackState>(
          stream: controller.playbackStream,
          initialData: controller.playbackState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? controller.playbackState;
            final playingId = playback.track?.id;
            return StreamBuilder<List<OfflineTrackDownload>>(
              stream: controller.offlineDownloadsStream,
              initialData: controller.offlineDownloads,
              builder: (context, _) {
                final album = _currentAlbum(controller);
                final localAlbum = album.toAlbum();
                final selectedTracks = _selectedTracks(album.tracks);
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          width: double.infinity,
                          child: Row(
                            children: [
                              CommandLinkButton(
                                label: 'Back to artist',
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              const Spacer(),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 10,
                                runSpacing: 10,
                                children: _selectionMode
                                    ? [
                                        DownloadSelectionToolbar(
                                          selectedCount: selectedTracks.length,
                                          totalCount: album.tracks.length,
                                          onCancel: _clearSelection,
                                          onSelectAll: () =>
                                              _selectAll(album.tracks),
                                          onDeselectAll: _deselectAll,
                                          onRemove: selectedTracks.isEmpty
                                              ? null
                                              : () => _removeDownloads(
                                                  context,
                                                  controller,
                                                  selectedTracks,
                                                  album.title,
                                                ),
                                        ),
                                      ]
                                    : [
                                        _editTrackSelectionButton(
                                          album.tracks.isNotEmpty
                                              ? _startSelection
                                              : null,
                                        ),
                                      ],
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
                          album: localAlbum,
                          coverUrl: album.coverPath ?? '',
                          headers: const {},
                        ),
                      ),
                    ),
                    if (album.tracks.isEmpty)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: EmptyState(
                            title: 'No downloaded tracks',
                            message:
                                'Downloaded tracks for this album appear here.',
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: TrackSliverList(
                          tracks: album.tracks,
                          isPlayingTrack: (track) =>
                              playback.isPlaying && playingId == track.id,
                          onTrackTap: (track) => controller.playOfflineTrack(
                            track.id,
                            tracks: album.tracks,
                          ),
                          onTrackAddToPlaylist: (track) =>
                              showAddToPlaylistModalForTrack(context, track),
                          onTrackLike: controller.toggleLocalLike,
                          selectionMode: _selectionMode,
                          isTrackSelected: (track) =>
                              _selectedTrackIds.contains(_selectionKey(track)),
                          onTrackSelectionToggle: _toggleSelection,
                          onTrackSelectionModeRequested: _enterSelection,
                          offlineDownloadForTrack: (track) =>
                              _offlineDownloadForTrack(controller, track),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _removeDownloads(
    BuildContext context,
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
    if (!confirmed || !context.mounted) {
      return;
    }
    final album = _currentAlbum(controller);
    await controller.removeDownloadedTracks(
      tracks,
      label: label,
      scope: tracks.length == album.tracks.length
          ? OfflineDeletionScope.album(id: album.id, label: label)
          : const OfflineDeletionScope.track(),
    );
    if (mounted) {
      _clearSelection();
    }
  }

  OfflineAlbumGroup _currentAlbum(AppController controller) {
    final groups = offlineArtistGroups(controller.offlineTracks);
    for (final artist in groups) {
      for (final album in artist.albums) {
        if (album.id == widget.album.id) {
          return album;
        }
      }
    }
    return OfflineAlbumGroup(
      id: widget.album.id,
      title: widget.album.title,
      artist: widget.album.artist,
      artistId: widget.album.artistId,
      tracks: const <Track>[],
      coverPath: widget.album.coverPath,
    );
  }

  List<Track> _selectedTracks(List<Track> tracks) {
    return tracks
        .where((track) => _selectedTrackIds.contains(_selectionKey(track)))
        .toList(growable: false);
  }

  OfflineTrackDownload? _offlineDownloadForTrack(
    AppController controller,
    Track track,
  ) {
    final available = controller.availableOfflineDownloadForTrack(track.id);
    return controller.offlineDownloadForTrack(track.id) ?? available;
  }

  void _enterSelection(Track track) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.add(_selectionKey(track));
    });
  }

  void _toggleSelection(Track track) {
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

  void _startSelection() {
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

  Widget _editTrackSelectionButton(VoidCallback? onPressed) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(
        icon: Icons.edit_rounded,
        onPressed: onPressed,
      ),
    );
  }

  String _selectionKey(Track track) {
    return track.localId ?? track.serverTrackId ?? track.id;
  }
}

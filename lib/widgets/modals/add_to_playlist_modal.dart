import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../layouts/app_scope.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import 'confirmation_modal.dart';

Future<void> showAddToPlaylistModalForTrack(
  BuildContext context,
  Track? track,
) async {
  if (track == null) {
    return;
  }
  final controller = AppScope.of(context);
  if (controller.localPlaylists.isEmpty) {
    await controller.loadLocalPlaylists();
  }
  if (controller.authState.isAuthorized && controller.playlists.isEmpty) {
    await controller.loadPlaylists();
  }
  if (!context.mounted) {
    return;
  }
  final localDownload = controller.availableOfflineDownloadForTrack(track.id);
  final canUseLocal = localDownload?.localTrackId != null;
  final serverTrack = controller.serverTrackForCurrentServer(track);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AddToPlaylistModal(
      localPlaylists: controller.localPlaylists,
      serverPlaylists: serverTrack != null && controller.authState.isAuthorized
          ? controller.playlists
          : const <Playlist>[],
      trackId: serverTrack?.id ?? track.id,
      localTrackId: track.localId ?? localDownload?.localTrackId,
      canUseLocalPlaylists: canUseLocal,
      onLocalSelected: (playlist) =>
          controller.addTrackToLocalPlaylist(playlist, track),
      onLocalRemoved: (playlist) =>
          controller.removeTrackFromLocalPlaylist(playlist, track),
      onServerSelected: (playlist) {
        final scopedTrack = serverTrack;
        if (scopedTrack != null) {
          controller.addTrackToPlaylist(playlist, scopedTrack);
        }
      },
      onServerRemoved: (playlist) {
        final scopedTrack = serverTrack;
        if (scopedTrack != null) {
          controller.removeTrackFromPlaylist(playlist, scopedTrack);
        }
      },
    ),
  );
}

class AddToPlaylistModal extends StatefulWidget {
  const AddToPlaylistModal({
    super.key,
    required this.localPlaylists,
    required this.serverPlaylists,
    required this.trackId,
    this.localTrackId,
    required this.canUseLocalPlaylists,
    required this.onLocalSelected,
    required this.onServerSelected,
    this.onLocalRemoved,
    this.onServerRemoved,
  });

  final List<Playlist> localPlaylists;
  final List<Playlist> serverPlaylists;
  final String trackId;
  final String? localTrackId;
  final bool canUseLocalPlaylists;
  final ValueChanged<Playlist> onLocalSelected;
  final ValueChanged<Playlist> onServerSelected;
  final ValueChanged<Playlist>? onLocalRemoved;
  final ValueChanged<Playlist>? onServerRemoved;

  @override
  State<AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends State<AddToPlaylistModal> {
  late final TextEditingController _controller;
  late final ScrollController _listController;
  String _query = '';
  final Set<String> _addedPlaylistIds = <String>{};
  final Set<String> _removedPlaylistIds = <String>{};

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _listController = ScrollController();
  }

  @override
  void dispose() {
    _listController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPlaylists =
        widget.localPlaylists.isNotEmpty || widget.serverPlaylists.isNotEmpty;
    final normalized = _query.trim().toLowerCase();
    final filteredLocal = _filterPlaylists(widget.localPlaylists, normalized);
    final filteredServer = _filterPlaylists(widget.serverPlaylists, normalized);

    return AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: hasPlaylists
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ObsidianTextField(
                    controller: _controller,
                    hintText: 'Search playlists',
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Scrollbar(
                      controller: _listController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _listController,
                        shrinkWrap: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                        itemCount: _rowCount(filteredLocal, filteredServer),
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: ObsidianPalette.textMuted.withValues(
                            alpha: 0.25,
                          ),
                        ),
                        itemBuilder: (context, index) {
                          final row = _rowAt(
                            index,
                            filteredLocal,
                            filteredServer,
                          );
                          if (row.header != null) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: Text(
                                row.header!,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: ObsidianPalette.gold,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                            );
                          }
                          return _buildPlaylistRow(
                            context,
                            row.playlist!,
                            isLocal: row.isLocal,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No playlists available.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Playlist> _filterPlaylists(List<Playlist> playlists, String normalized) {
    return playlists.where((playlist) {
      if (normalized.isEmpty) {
        return true;
      }
      return playlist.name.toLowerCase().contains(normalized);
    }).toList();
  }

  int _rowCount(List<Playlist> local, List<Playlist> server) {
    return (local.isEmpty ? 0 : local.length + 1) +
        (server.isEmpty ? 0 : server.length + 1);
  }

  _PlaylistModalRow _rowAt(
    int index,
    List<Playlist> local,
    List<Playlist> server,
  ) {
    var cursor = index;
    if (local.isNotEmpty) {
      if (cursor == 0) {
        return const _PlaylistModalRow.header('Local Playlists');
      }
      cursor -= 1;
      if (cursor < local.length) {
        return _PlaylistModalRow.playlist(local[cursor], isLocal: true);
      }
      cursor -= local.length;
    }
    if (server.isNotEmpty) {
      if (cursor == 0) {
        return const _PlaylistModalRow.header('Server Playlists');
      }
      cursor -= 1;
      return _PlaylistModalRow.playlist(server[cursor], isLocal: false);
    }
    return const _PlaylistModalRow.header('');
  }

  Widget _buildPlaylistRow(
    BuildContext context,
    Playlist playlist, {
    required bool isLocal,
  }) {
    final membershipId = isLocal
        ? widget.localTrackId ?? widget.trackId
        : widget.trackId;
    final wasInPlaylist = playlist.trackIds.contains(membershipId);
    final addedLocally = _addedPlaylistIds.contains(playlist.id);
    final removedLocally = _removedPlaylistIds.contains(playlist.id);
    final isInPlaylist = (wasInPlaylist || addedLocally) && !removedLocally;
    var count = playlist.trackIds.length;
    if (wasInPlaylist && removedLocally) {
      count -= 1;
    } else if (!wasInPlaylist && addedLocally) {
      count += 1;
    }
    final localDisabled = isLocal && !widget.canUseLocalPlaylists;
    final removable = isLocal ? widget.onLocalRemoved : widget.onServerRemoved;
    final select = isLocal ? widget.onLocalSelected : widget.onServerSelected;

    return _ModalListRow(
      title: playlist.name,
      subtitle: localDisabled
          ? 'Download this song first'
          : '${isLocal ? 'Local' : 'Server'} - $count tracks',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInPlaylist ? Icons.check_rounded : Icons.add_rounded,
            color: localDisabled
                ? ObsidianPalette.textMuted
                : ObsidianPalette.gold,
          ),
          if (isInPlaylist && removable != null) ...[
            const SizedBox(width: 8),
            ObsidianHudIconButton(
              icon: Icons.delete_outline_rounded,
              onPressed: () async {
                final confirmed = await ConfirmationModal.show(
                  context,
                  title: 'Remove song from playlist',
                  message:
                      'Are you sure you want to remove this song from this playlist?',
                );
                if (!confirmed || !mounted) {
                  return;
                }
                removable.call(playlist);
                setState(() {
                  _removedPlaylistIds.add(playlist.id);
                  _addedPlaylistIds.remove(playlist.id);
                });
              },
              size: 20,
            ),
          ],
        ],
      ),
      enabled: !isInPlaylist && !localDisabled,
      isSelected: isInPlaylist,
      onTap: isInPlaylist || localDisabled
          ? null
          : () {
              select(playlist);
              setState(() {
                _addedPlaylistIds.add(playlist.id);
                _removedPlaylistIds.remove(playlist.id);
              });
            },
    );
  }
}

class _PlaylistModalRow {
  const _PlaylistModalRow.header(this.header)
    : playlist = null,
      isLocal = false;

  const _PlaylistModalRow.playlist(this.playlist, {required this.isLocal})
    : header = null;

  final String? header;
  final Playlist? playlist;
  final bool isLocal;
}

class _ModalListRow extends StatelessWidget {
  const _ModalListRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    required this.enabled,
    required this.isSelected,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: enabled ? ObsidianPalette.textPrimary : ObsidianPalette.textMuted,
      letterSpacing: 0.4,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: ObsidianPalette.textMuted,
    );

    return ObsidianHoverRow(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      isActive: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

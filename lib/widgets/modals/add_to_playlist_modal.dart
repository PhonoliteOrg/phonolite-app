import 'package:flutter/material.dart';

import '../../entities/app_controller.dart';
import '../../entities/models.dart';
import '../layouts/app_scope.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import 'confirmation_modal.dart';

Future<void> showAddToPlaylistModalForTrack(
  BuildContext context,
  Track? track, {
  required ActionScope scope,
}) async {
  if (track == null) {
    return;
  }
  final controller = AppScope.of(context);
  final isLocal = scope == ActionScope.local;
  if (isLocal) {
    if (controller.localPlaylists.isEmpty) {
      await controller.loadLocalPlaylists();
    }
  } else if (controller.authState.isAuthorized &&
      controller.playlists.isEmpty) {
    await controller.loadPlaylists();
  }
  if (!context.mounted) {
    return;
  }
  final localDownload = isLocal
      ? controller.availableOfflineDownloadForTrack(track.id)
      : null;
  final localTrackId = track.localId ?? localDownload?.localTrackId;
  final serverTrack = isLocal
      ? null
      : controller.serverTrackForCurrentServer(track);
  final canUsePlaylists = isLocal
      ? localTrackId != null
      : serverTrack != null && controller.authState.isAuthorized;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AddToPlaylistModal(
      scope: scope,
      playlists: isLocal ? controller.localPlaylists : controller.playlists,
      trackId: isLocal ? localTrackId ?? track.id : serverTrack?.id ?? track.id,
      canUsePlaylists: canUsePlaylists,
      onSelected: (playlist) {
        if (isLocal) {
          controller.addTrackToLocalPlaylist(playlist, track);
          return;
        }
        final scopedTrack = serverTrack;
        if (scopedTrack != null) {
          controller.addTrackToPlaylist(playlist, scopedTrack);
        }
      },
      onRemoved: (playlist) {
        if (isLocal) {
          controller.removeTrackFromLocalPlaylist(playlist, track);
          return;
        }
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
    required this.scope,
    required this.playlists,
    required this.trackId,
    required this.canUsePlaylists,
    required this.onSelected,
    this.onRemoved,
  });

  final ActionScope scope;
  final List<Playlist> playlists;
  final String trackId;
  final bool canUsePlaylists;
  final ValueChanged<Playlist> onSelected;
  final ValueChanged<Playlist>? onRemoved;

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
    final hasPlaylists = widget.playlists.isNotEmpty;
    final normalized = _query.trim().toLowerCase();
    final filteredPlaylists = _filterPlaylists(widget.playlists, normalized);
    final scopeLabel = widget.scope == ActionScope.local ? 'local' : 'server';

    return AlertDialog(
      title: Text('Add to $scopeLabel playlist'),
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
                        itemCount: filteredPlaylists.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: ObsidianPalette.textMuted.withValues(
                            alpha: 0.25,
                          ),
                        ),
                        itemBuilder: (context, index) {
                          return _buildPlaylistRow(
                            context,
                            filteredPlaylists[index],
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
                  'No $scopeLabel playlists available.',
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

  Widget _buildPlaylistRow(BuildContext context, Playlist playlist) {
    final wasInPlaylist = playlist.trackIds.contains(widget.trackId);
    final addedLocally = _addedPlaylistIds.contains(playlist.id);
    final removedLocally = _removedPlaylistIds.contains(playlist.id);
    final isInPlaylist = (wasInPlaylist || addedLocally) && !removedLocally;
    var count = playlist.trackIds.length;
    if (wasInPlaylist && removedLocally) {
      count -= 1;
    } else if (!wasInPlaylist && addedLocally) {
      count += 1;
    }
    final disabled = !widget.canUsePlaylists;
    final scopeLabel = widget.scope == ActionScope.local ? 'Local' : 'Server';

    return _ModalListRow(
      title: playlist.name,
      subtitle: disabled
          ? widget.scope == ActionScope.local
                ? 'Download this song first'
                : 'Unavailable on this server'
          : '$scopeLabel - $count tracks',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInPlaylist ? Icons.check_rounded : Icons.add_rounded,
            color: disabled ? ObsidianPalette.textMuted : ObsidianPalette.gold,
          ),
          if (isInPlaylist && widget.onRemoved != null) ...[
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
                widget.onRemoved!.call(playlist);
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
      enabled: !isInPlaylist && !disabled,
      isSelected: isInPlaylist,
      onTap: isInPlaylist || disabled
          ? null
          : () {
              widget.onSelected(playlist);
              setState(() {
                _addedPlaylistIds.add(playlist.id);
                _removedPlaylistIds.remove(playlist.id);
              });
            },
    );
  }
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

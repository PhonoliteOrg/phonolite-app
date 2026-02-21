import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

class AddToPlaylistModal extends StatefulWidget {
  const AddToPlaylistModal({
    super.key,
    required this.playlists,
    required this.trackId,
    required this.onSelected,
    this.onRemoved,
  });

  final List<Playlist> playlists;
  final String trackId;
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
    final filtered = widget.playlists.where((playlist) {
      if (normalized.isEmpty) {
        return true;
      }
      return playlist.name.toLowerCase().contains(normalized);
    }).toList();

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
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: ObsidianPalette.textMuted.withOpacity(0.25),
                        ),
                        itemBuilder: (context, index) {
                          final playlist = filtered[index];
                          final wasInPlaylist =
                              playlist.trackIds.contains(widget.trackId);
                          final addedLocally =
                              _addedPlaylistIds.contains(playlist.id);
                          final removedLocally =
                              _removedPlaylistIds.contains(playlist.id);
                          final isInPlaylist =
                              (wasInPlaylist || addedLocally) && !removedLocally;
                          var count = playlist.trackIds.length;
                          if (wasInPlaylist && removedLocally) {
                            count -= 1;
                          } else if (!wasInPlaylist && addedLocally) {
                            count += 1;
                          }
                          return _ModalListRow(
                            title: playlist.name,
                            subtitle: '$count tracks',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isInPlaylist
                                      ? Icons.check_rounded
                                      : Icons.add_rounded,
                                  color: ObsidianPalette.gold,
                                ),
                                if (isInPlaylist && widget.onRemoved != null) ...[
                                  const SizedBox(width: 8),
                                  ObsidianHudIconButton(
                                    icon: Icons.delete_outline_rounded,
                                    onPressed: () {
                                      widget.onRemoved?.call(playlist);
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
                            enabled: !isInPlaylist,
                            isSelected: isInPlaylist,
                            onTap: isInPlaylist
                                ? null
                                : () {
                                    widget.onSelected(playlist);
                                    setState(() {
                                      _addedPlaylistIds.add(playlist.id);
                                      _removedPlaylistIds.remove(playlist.id);
                                    });
                                  },
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
      color: enabled
          ? ObsidianPalette.textPrimary
          : ObsidianPalette.textMuted,
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

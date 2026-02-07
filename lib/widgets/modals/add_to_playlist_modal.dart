import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/obsidian_theme.dart';

class AddToPlaylistModal extends StatefulWidget {
  const AddToPlaylistModal({
    super.key,
    required this.playlists,
    required this.trackId,
    required this.onSelected,
  });

  final List<Playlist> playlists;
  final String trackId;
  final ValueChanged<Playlist> onSelected;

  @override
  State<AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends State<AddToPlaylistModal> {
  late final TextEditingController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ObsidianTextField(
              controller: _controller,
              hintText: 'Search playlists',
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: ObsidianPalette.textMuted.withOpacity(0.25),
                ),
                itemBuilder: (context, index) {
                  final playlist = filtered[index];
                  final alreadyAdded =
                      playlist.trackIds.contains(widget.trackId);
                    return _ModalListRow(
                      title: playlist.name,
                      subtitle: '${playlist.trackIds.length} tracks',
                      trailing: Icon(
                        alreadyAdded ? Icons.check_rounded : Icons.add_rounded,
                        color: ObsidianPalette.gold,
                      ),
                    enabled: !alreadyAdded,
                    isSelected: alreadyAdded,
                    onTap: alreadyAdded
                        ? null
                        : () {
                            widget.onSelected(playlist);
                            Navigator.of(context).pop();
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ModalListRow extends StatefulWidget {
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
  State<_ModalListRow> createState() => _ModalListRowState();
}

class _ModalListRowState extends State<_ModalListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = widget.isSelected || _hovered;
    final borderColor = highlight ? ObsidianPalette.gold : Colors.transparent;
    final background = _hovered
        ? LinearGradient(
            colors: [
              Colors.white.withOpacity(0.06),
              Colors.transparent,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : null;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: widget.enabled
          ? ObsidianPalette.textPrimary
          : ObsidianPalette.textMuted,
      letterSpacing: 0.4,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: ObsidianPalette.textMuted,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: borderColor, width: 2)),
              gradient: background,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                widget.trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

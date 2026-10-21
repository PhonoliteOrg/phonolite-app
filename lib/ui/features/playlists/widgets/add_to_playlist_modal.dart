import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/add_to_playlist_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/structures/modals/base_alert_modal.dart';

Future<void> showAddToPlaylistModalForTrack(BuildContext context, Track? track, {required ActionScope scope}) async {
  if (track == null) {
    return;
  }

  final controller = AppScope.of(context);
  final actions = await AddToPlaylistController.prepareActions(controller, track, scope);

  if (!context.mounted || actions == null) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AddToPlaylistModal(
      scope: scope,
      playlists: actions.playlists,
      trackId: actions.trackId,
      canUsePlaylists: actions.canUsePlaylists,
      onSelected: actions.add,
      onRemoved: actions.remove,
    ),
  );
}

class AddToPlaylistModal extends BaseAlertModal {
  final ActionScope scope;
  final List<Playlist> playlists;
  final String trackId;
  final bool canUsePlaylists;
  final ValueChanged<Playlist> onSelected;
  final ValueChanged<Playlist>? onRemoved;

  const AddToPlaylistModal({
    super.key,
    required this.scope,
    required this.playlists,
    required this.trackId,
    required this.canUsePlaylists,
    required this.onSelected,
    this.onRemoved,
  });

  @override
  State<AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends BaseAlertModalState<AddToPlaylistModal> {
  late final AddToPlaylistController _feature = bindController(AddToPlaylistController());
  late final TextEditingController _controller;
  late final ScrollController _listController;

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
  Widget modalTitle(BuildContext context) =>
      Text('Add to ${widget.scope == ActionScope.local ? 'local' : 'server'} playlist');

  void _updateQuery() {
    _feature.setQuery(_controller.text);
  }

  Future<void> _confirmRemoval(BuildContext context, Playlist playlist) async {
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Remove song from playlist',
      message: 'Are you sure you want to remove this song from this playlist?',
    );

    if (!confirmed || !mounted) {
      return;
    }

    _feature.remove(playlist, widget.onRemoved!);
  }

  Widget _buildPlaylistRow(BuildContext context, Playlist playlist) {
    final isInPlaylist = _feature.contains(playlist, widget.trackId);
    final count = _feature.trackCount(playlist, widget.trackId);
    final disabled = !widget.canUsePlaylists;
    final scopeLabel = widget.scope == ActionScope.local ? 'Local' : 'Server';
    final onAdd = isInPlaylist || disabled ? null : () => _feature.add(playlist, widget.onSelected);

    final String subtitle;

    if (disabled) {
      subtitle = widget.scope == ActionScope.local ? 'Download this song first' : 'Unavailable on this server';
    } else {
      subtitle = '$scopeLabel - $count tracks';
    }

    return ObsidianModalListRow(
      title: playlist.name,
      subtitle: subtitle,
      trailing: Tooltip(
        message: isInPlaylist ? 'Remove from playlist' : 'Add to playlist',
        child: ObsidianHudIconButton(
          icon: isInPlaylist ? PhonoliteIcons.trash2 : PhonoliteIcons.plus,
          size: ObsidianModalScope.usesTouchTargets(context) ? 24 : 20,
          onPressed: isInPlaylist && widget.onRemoved != null ? () => _confirmRemoval(context, playlist) : onAdd,
        ),
      ),
      enabled: !isInPlaylist && !disabled,
      isSelected: isInPlaylist,
      onTap: onAdd,
    );
  }

  @override
  Widget modalContent(BuildContext context) {
    final hasPlaylists = widget.playlists.isNotEmpty;
    final filteredPlaylists = _feature.filter(widget.playlists);
    final scopeLabel = widget.scope == ActionScope.local ? 'local' : 'server';

    return SizedBox(
      width: 360,
      height: 420,
      child: hasPlaylists
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchHud(
                  controller: _controller,
                  height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
                  hintText: 'Search playlists',
                  onChanged: _updateQuery,
                  onSubmit: _updateQuery,
                  onClear: _updateQuery,
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
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: ObsidianPalette.textMuted.withValues(alpha: 0.25)),
                      itemBuilder: (context, index) {
                        return _buildPlaylistRow(context, filteredPlaylists[index]);
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
              ),
            ),
    );
  }

  @override
  List<Widget> modalActions(BuildContext context) => [
    ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
  ];
}

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

IconData searchResultIconForKind(String kind) {
  switch (kind) {
    case 'artist':
      return PhonoliteIcons.userRound;
    case 'album':
      return PhonoliteIcons.disc3;
    case 'track':
      return PhonoliteIcons.music;
    default:
      return PhonoliteIcons.search;
  }
}

class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  final CatalogController? catalog;
  final Map<String, String> headers;
  final bool useLocalArtwork;

  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.catalog,
    this.headers = const {},
    this.useLocalArtwork = false,
  });

  Future<List<ObsidianMenuAction>> _resolveTrackActions(BuildContext context, AppController controller) async {
    final track = await (catalog ?? controller.catalog).resolveSearchTrack(
      result,
      local: useLocalArtwork,
      offlineTracks: controller.offlineTracks,
    );

    return TrackRowTile.menuActionsFor(
      track: track,
      offlineDownload: controller.offlineDownloadForTrack(track.id),
      onLike: () => useLocalArtwork ? controller.toggleLocalLike(track) : controller.toggleLike(track),
      onDownload: useLocalArtwork ? null : () => controller.downloadTrack(track),
      onAddToPlaylist: () => showAddToPlaylistModalForTrack(
        context,
        track,
        scope: useLocalArtwork ? ActionScope.local : ActionScope.server,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = isCompactListWidth(context);
    final controller = context.dependOnInheritedWidgetOfExactType<AppScope>()?.controller;
    final showTrackActions = result.kind == 'track' && controller != null && ObsidianModalScope.isCompact(context);

    return ObsidianListRow(
      onTap: onTap,
      title: result.title,
      subtitle: result.subtitle,
      subtitleColor: Colors.white60,
      leading: _SearchResultArtwork(
        key: ValueKey('${result.kind}:${result.id}'),
        result: result,
        catalog: catalog,
        headers: headers,
        useLocalArtwork: useLocalArtwork,
        size: isCompact ? 42 : 48,
        badgeSize: isCompact ? 20 : 22,
      ),
      trailing: showTrackActions
          ? SizedBox.square(
              dimension: 44,
              child: ObsidianOverflowActionButton(
                tooltip: 'Track actions',
                modalTitle: result.title,
                size: isCompact ? 18 : 22,
                actions: const [],
                resolveActions: () => _resolveTrackActions(context, controller),
              ),
            )
          : Icon(PhonoliteIcons.chevronRight, size: isCompact ? 22 : 24, color: Colors.white38),
    );
  }
}

class _SearchResultArtwork extends StatefulWidget {
  final SearchResult result;
  final CatalogController? catalog;
  final Map<String, String> headers;
  final bool useLocalArtwork;
  final double size;
  final double badgeSize;

  const _SearchResultArtwork({
    super.key,
    required this.result,
    required this.catalog,
    required this.headers,
    required this.useLocalArtwork,
    required this.size,
    required this.badgeSize,
  });

  @override
  State<_SearchResultArtwork> createState() => _SearchResultArtworkState();
}

class _SearchResultArtworkState extends State<_SearchResultArtwork> {
  Future<String?>? _legacyTrackCover;

  @override
  void initState() {
    super.initState();

    _resolveLegacyTrackCover();
  }

  @override
  void didUpdateWidget(_SearchResultArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.result.id != widget.result.id ||
        oldWidget.result.kind != widget.result.kind ||
        oldWidget.result.albumId != widget.result.albumId ||
        oldWidget.catalog != widget.catalog ||
        oldWidget.useLocalArtwork != widget.useLocalArtwork) {
      _resolveLegacyTrackCover();
    }
  }

  void _resolveLegacyTrackCover() {
    _legacyTrackCover = widget.useLocalArtwork ? null : widget.catalog?.legacySearchArtwork(widget.result);
  }

  Widget _artwork(String? imageUrl) {
    final size = widget.size;
    final badgeSize = widget.badgeSize;
    // Reserve the part outside the image so adjacent text and rows stay clear.
    final spill = badgeSize / 2;

    return SizedBox(
      width: size + spill,
      height: size + spill,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: size,
            height: size,
            child: ClipRect(
              child: ColoredBox(
                color: ObsidianPalette.obsidianElevated,
                child: AlbumArt(
                  title: widget.result.title,
                  size: size,
                  imageUrl: imageUrl,
                  headers: widget.useLocalArtwork ? const {} : widget.headers,
                  fit: widget.result.kind == 'artist' ? BoxFit.contain : BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            left: size - spill,
            top: size - spill,
            width: badgeSize,
            height: badgeSize,
            child: Icon(searchResultIconForKind(widget.result.kind), size: badgeSize, color: ObsidianPalette.gold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_legacyTrackCover != null) {
      return FutureBuilder<String?>(future: _legacyTrackCover, builder: (context, snapshot) => _artwork(snapshot.data));
    }

    return _artwork(widget.useLocalArtwork ? widget.result.artworkPath : widget.catalog?.searchArtwork(widget.result));
  }
}

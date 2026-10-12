import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';

import '../../entities/models.dart';
import '../../entities/server_connection.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/responsive_breakpoints.dart';
import 'album_art.dart';

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
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.connection,
    this.headers = const {},
    this.useLocalArtwork = false,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final ServerConnection? connection;
  final Map<String, String> headers;
  final bool useLocalArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = isCompactListWidth(context);
    return ObsidianHoverRow(
      onTap: onTap,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _SearchResultArtwork(
            key: ValueKey('${result.kind}:${result.id}'),
            result: result,
            connection: connection,
            headers: headers,
            useLocalArtwork: useLocalArtwork,
            size: isCompact ? 42 : 48,
            badgeSize: isCompact ? 20 : 22,
          ),
          SizedBox(width: isCompact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: isCompact ? 14.5 : null,
                    letterSpacing: isCompact ? 0.2 : 0.6,
                  ),
                ),
                if (result.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: isCompact ? 12 : null,
                      letterSpacing: isCompact ? 0 : null,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            PhonoliteIcons.chevronRight,
            size: isCompact ? 22 : 24,
            color: Colors.white38,
          ),
        ],
      ),
    );
  }
}

class _SearchResultArtwork extends StatefulWidget {
  const _SearchResultArtwork({
    super.key,
    required this.result,
    required this.connection,
    required this.headers,
    required this.useLocalArtwork,
    required this.size,
    required this.badgeSize,
  });

  final SearchResult result;
  final ServerConnection? connection;
  final Map<String, String> headers;
  final bool useLocalArtwork;
  final double size;
  final double badgeSize;

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
        oldWidget.connection != widget.connection ||
        oldWidget.useLocalArtwork != widget.useLocalArtwork) {
      _resolveLegacyTrackCover();
    }
  }

  void _resolveLegacyTrackCover() {
    final connection = widget.connection;
    final result = widget.result;
    // Older server versions omit album_id from track search results.
    _legacyTrackCover =
        !widget.useLocalArtwork &&
            connection != null &&
            result.kind == 'track' &&
            (result.albumId?.trim().isEmpty ?? true)
        ? _fetchLegacyTrackCover(connection, result.id)
        : null;
  }

  Future<String?> _fetchLegacyTrackCover(
    ServerConnection connection,
    String trackId,
  ) async {
    try {
      final track = await connection.fetchTrackById(trackId);
      final albumId = track.albumId;
      return albumId == null || albumId.isEmpty
          ? null
          : connection.buildAlbumCoverUrl(albumId);
    } catch (_) {
      return null;
    }
  }

  String? _imageUrl() {
    if (widget.useLocalArtwork) return widget.result.artworkPath;
    final connection = widget.connection;
    if (connection == null) return null;
    final result = widget.result;
    switch (result.kind) {
      case 'artist':
        return connection.buildArtistCoverUrl(result.id, kind: 'logo');
      case 'album':
        return connection.buildAlbumCoverUrl(result.id);
      case 'track':
        final albumId = result.albumId?.trim();
        return albumId == null || albumId.isEmpty
            ? null
            : connection.buildAlbumCoverUrl(albumId);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_legacyTrackCover != null) {
      return FutureBuilder<String?>(
        future: _legacyTrackCover,
        builder: (context, snapshot) => _artwork(snapshot.data),
      );
    }
    return _artwork(_imageUrl());
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
                  fit: widget.result.kind == 'artist'
                      ? BoxFit.contain
                      : BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            left: size - spill,
            top: size - spill,
            width: badgeSize,
            height: badgeSize,
            child: Icon(
              searchResultIconForKind(widget.result.kind),
              size: badgeSize,
              color: ObsidianPalette.gold,
            ),
          ),
        ],
      ),
    );
  }
}

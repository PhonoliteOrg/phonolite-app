import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/card_image_frame.dart';
import 'package:phonolite_app/ui/shared/music/media_card_body.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';
import 'package:phonolite_app/ui/shared/music/selectable_media_card.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final bool isDeleting;
  final VoidCallback? onSelectionToggle;

  const AlbumCard({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onLongPress,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    double t(double value) => MediaCardBody.textSize(context, value);

    return SelectableMediaCard(
      onTap: onTap,
      onLongPress: onLongPress,
      selection: MediaSelection(
        selectionMode: selectionMode,
        selected: selected,
        selectable: selectable,
        isDeleting: isDeleting,
        onSelectionToggle: onSelectionToggle,
      ),
      contentBuilder: (context, constraints, hovered) {
        final minImageSize = t(80.0);
        final maxImageSize = math.min(t(albumPortraitSize), constraints.maxWidth);
        final reservedTextHeight = t(48.0);
        final availableForImage = (constraints.maxHeight - reservedTextHeight).clamp(
          minImageSize,
          t(albumPortraitSize),
        );
        final imageSize = math.min(maxImageSize, availableForImage);

        return MediaCardBody(
          title: album.title,
          artwork: CardImageFrame(
            hovered: hovered,
            borderRadius: BorderRadius.zero,
            child: AlbumArt(title: album.title, size: imageSize, imageUrl: coverUrl, headers: headers),
          ),
        );
      },
    );
  }
}

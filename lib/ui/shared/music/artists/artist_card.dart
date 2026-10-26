import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artist_avatar.dart';
import 'package:phonolite_app/ui/shared/music/artwork/card_image_frame.dart';
import 'package:phonolite_app/ui/shared/music/media_card_body.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';
import 'package:phonolite_app/ui/shared/music/selectable_media_card.dart';

class ArtistCard extends StatelessWidget {
  final Artist artist;
  final String? coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final bool isDeleting;
  final VoidCallback? onSelectionToggle;

  const ArtistCard({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    double t(double value) => MediaCardBody.textSize(context, value);

    return SelectableMediaCard(
      onTap: onTap,
      selection: MediaSelection(
        selectionMode: selectionMode,
        selected: selected,
        selectable: selectable,
        isDeleting: isDeleting,
        onSelectionToggle: onSelectionToggle,
      ),
      contentBuilder: (context, constraints, hovered) {
        final imageSize = math.min(
          t(170),
          math.max(0.0, math.min(constraints.maxWidth - 4, constraints.maxHeight - t(42) - 4)),
        );

        final content = MediaCardBody(
          title: artist.name,
          fontSize: 18,
          artworkGap: 12,
          letterSpacing: 1.1,
          mainAxisSize: MainAxisSize.min,
          artwork: CardImageFrame(
            hovered: hovered,
            child: ArtistAvatar(
              name: artist.name,
              size: imageSize,
              imageUrl: coverUrl,
              headers: headers,
              fit: BoxFit.contain,
              paddingFraction: 0,
              thumbnail: true,
            ),
          ),
        );

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(width: constraints.maxWidth, child: content),
        );
      },
    );
  }
}

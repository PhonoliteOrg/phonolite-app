import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// A list-and-pencil icon for editing playlists and song collections.
class PlaylistEditIcon extends StatelessWidget {
  const PlaylistEditIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(
      assetName: 'assets/icons/tabler/playlist-edit.svg',
    );
  }
}

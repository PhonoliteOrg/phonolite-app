import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// The bundled Tabler playlist-add icon.
class PlaylistAddIcon extends StatelessWidget {
  const PlaylistAddIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(
      assetName: 'assets/icons/tabler/playlist-add.svg',
    );
  }
}

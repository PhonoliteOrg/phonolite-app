import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// The bundled playlist icon with a compact filled music note.
class PlaylistIcon extends StatelessWidget {
  const PlaylistIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(assetName: 'assets/icons/tabler/playlist.svg');
  }
}

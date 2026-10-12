import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// The bundled Tabler reload icon.
class ReloadIcon extends StatelessWidget {
  const ReloadIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(assetName: 'assets/icons/tabler/reload.svg');
  }
}

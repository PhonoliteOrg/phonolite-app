import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// The bundled Tabler edit icon.
class EditIcon extends StatelessWidget {
  const EditIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(assetName: 'assets/icons/tabler/edit.svg');
  }
}

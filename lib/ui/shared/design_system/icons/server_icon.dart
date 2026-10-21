import 'package:flutter/widgets.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';

/// The bundled Tabler cloud icon used to identify the server.
class ServerIcon extends StatelessWidget {
  const ServerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SvgAssetIcon(assetName: 'assets/icons/tabler/cloud.svg');
  }
}

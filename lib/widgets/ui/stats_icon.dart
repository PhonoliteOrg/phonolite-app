import 'package:flutter/widgets.dart';

import 'svg_asset_icon.dart';

/// Bundled Stats icons with the tallest bar in the middle and optional badges.
class StatsIcon extends StatelessWidget {
  const StatsIcon({super.key, this.size})
    : _assetName = 'assets/icons/tabler/brand-google-analytics.svg';

  const StatsIcon.deviceReset({super.key, this.size})
    : _assetName = 'assets/icons/tabler/stats-reset-device.svg';

  const StatsIcon.accountReset({super.key, this.size})
    : _assetName = 'assets/icons/tabler/stats-reset-account.svg';

  final double? size;
  final String _assetName;

  @override
  Widget build(BuildContext context) {
    return SvgAssetIcon(assetName: _assetName, size: size);
  }
}

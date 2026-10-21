import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';

SliverFillRemaining loadingSliver() {
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(accentGold)),
      ),
    ),
  );
}

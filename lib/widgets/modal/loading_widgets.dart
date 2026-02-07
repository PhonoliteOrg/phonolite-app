import 'package:flutter/material.dart';

import '../../core/constants.dart';

SliverFillRemaining loadingSliver() {
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(accentGold),
        ),
      ),
    ),
  );
}

Widget heroLoadingBox({required double height}) {
  return SizedBox(
    height: height,
    child: Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(accentGold),
        ),
      ),
    ),
  );
}

Widget fullPageSpinner() {
  return const Center(
    child: SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(accentGold),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

bool settingsUsesManagedOfflineStoragePaths(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.iOS;
}

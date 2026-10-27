import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/app/desktop_window_configuration.dart';

const double obsidianCompactListBreakpoint = 640;
const double obsidianExpandedLayoutBreakpoint = 980;

enum ObsidianLayoutMode { compact, narrow, expanded }

/// Mobile windows need room in both dimensions, so rotating a phone does not
/// select a desktop shell. Short tiled desktop windows keep their side rail.
ObsidianLayoutMode obsidianLayoutModeFor(Size size, TargetPlatform platform) {
  final desktop = switch (platform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
  };

  if (size.width < DesktopWindowConfiguration.minimumWidth ||
      (!desktop && size.shortestSide < DesktopWindowConfiguration.minimumWidth)) {
    return ObsidianLayoutMode.compact;
  }

  return size.width < obsidianExpandedLayoutBreakpoint ? ObsidianLayoutMode.narrow : ObsidianLayoutMode.expanded;
}

ObsidianLayoutMode obsidianLayoutModeOf(BuildContext context) =>
    obsidianLayoutModeFor(MediaQuery.sizeOf(context), Theme.of(context).platform);

bool usesSideNavigation(BuildContext context) => obsidianLayoutModeOf(context) != ObsidianLayoutMode.compact;

bool isCompactListWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < obsidianCompactListBreakpoint;
}

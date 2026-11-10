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

/// Breakpoint answers for the surrounding viewport.
///
/// Dependents rebuild only when a breakpoint is crossed, not on every window
/// resize frame the way a [MediaQuery.sizeOf] dependency would.
class ObsidianBreakpoints extends InheritedWidget {
  final ObsidianLayoutMode layoutMode;
  final bool compactList;

  const ObsidianBreakpoints({super.key, required this.layoutMode, required this.compactList, required super.child});

  ObsidianBreakpoints.resolve(BuildContext context, {Key? key, required Widget child})
    : this._fromSize(key: key, size: MediaQuery.sizeOf(context), platform: Theme.of(context).platform, child: child);

  ObsidianBreakpoints._fromSize({super.key, required Size size, required TargetPlatform platform, required super.child})
    : layoutMode = obsidianLayoutModeFor(size, platform),
      compactList = size.width < obsidianCompactListBreakpoint;

  static ObsidianBreakpoints? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ObsidianBreakpoints>();

  @override
  bool updateShouldNotify(ObsidianBreakpoints oldWidget) =>
      oldWidget.layoutMode != layoutMode || oldWidget.compactList != compactList;
}

ObsidianLayoutMode obsidianLayoutModeOf(BuildContext context) =>
    ObsidianBreakpoints.maybeOf(context)?.layoutMode ??
    obsidianLayoutModeFor(MediaQuery.sizeOf(context), Theme.of(context).platform);

bool usesSideNavigation(BuildContext context) => obsidianLayoutModeOf(context) != ObsidianLayoutMode.compact;

bool isCompactListWidth(BuildContext context) =>
    ObsidianBreakpoints.maybeOf(context)?.compactList ??
    MediaQuery.sizeOf(context).width < obsidianCompactListBreakpoint;

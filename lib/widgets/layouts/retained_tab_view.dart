import 'package:flutter/material.dart';

import 'obsidian_scale.dart';
import 'playback_content_inset.dart';

typedef _TabViewport = ({
  MediaQueryData media,
  ThemeData theme,
  double scale,
  double playbackInset,
});

/// Keeps each tab mounted, but only lays out and paints the active tab.
///
/// Unlike IndexedStack or Offstage, an opaque overlay entry prevents covered
/// entries from participating in viewport layout. Overlay also suspends their
/// tickers. The number and order of tabs must remain stable.
class RetainedTabView extends StatefulWidget {
  const RetainedTabView({
    super.key,
    required this.index,
    required this.children,
  }) : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  State<RetainedTabView> createState() => _RetainedTabViewState();
}

class _RetainedTabViewState extends State<RetainedTabView> {
  final _overlayKey = GlobalKey<OverlayState>();
  late final List<OverlayEntry> _entries;
  late final List<_TabViewport?> _viewports;

  @override
  void initState() {
    super.initState();
    _viewports = List.filled(widget.children.length, null);
    _entries = List.generate(
      widget.children.length,
      (index) => OverlayEntry(
        opaque: true,
        maintainState: true,
        builder: (context) {
          final viewport = _viewports[index]!;
          return MediaQuery(
            data: viewport.media,
            child: Theme(
              data: viewport.theme,
              child: ObsidianScale(
                scale: viewport.scale,
                child: PlaybackContentInset(
                  bottom: viewport.playbackInset,
                  child: ExcludeFocus(
                    excluding: index != widget.index,
                    child: RepaintBoundary(child: widget.children[index]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<OverlayEntry> get _orderedEntries => [
    for (var i = 0; i < _entries.length; i++)
      if (i != widget.index) _entries[i],
    _entries[widget.index],
  ];

  @override
  void didUpdateWidget(covariant RetainedTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.children.length == widget.children.length);
    for (var i = 0; i < _entries.length; i++) {
      if (oldWidget.index != widget.index ||
          oldWidget.children[i] != widget.children[i]) {
        _entries[i].markNeedsBuild();
      }
    }
    if (oldWidget.index != widget.index) {
      _overlayKey.currentState!.rearrange(_orderedEntries);
    }
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.remove();
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = (
      media: MediaQuery.of(context),
      theme: Theme.of(context),
      scale: ObsidianScale.of(context),
      playbackInset: PlaybackContentInset.bottomOf(context),
    );
    // Covered overlay entries can still rebuild if they inherit new viewport
    // data. Freeze their metrics until selected, including the player clearance.
    for (var i = 0; i < _viewports.length; i++) {
      _viewports[i] ??= viewport;
    }
    if (_viewports[widget.index] != viewport) {
      _viewports[widget.index] = viewport;
      _entries[widget.index].markNeedsBuild();
    }
    return Overlay(key: _overlayKey, initialEntries: _orderedEntries);
  }
}

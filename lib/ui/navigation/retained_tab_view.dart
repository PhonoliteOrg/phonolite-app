import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/navigation/obsidian_page_transitions.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

typedef _TabViewport = ({MediaQueryData media, ThemeData theme, double scale, double topInset, double playbackInset});

/// Keeps each tab mounted, but only lays out and paints the active tab.
/// Replacing a stack briefly retains the outgoing content for its transition.
///
/// Unlike IndexedStack or Offstage, an opaque overlay entry prevents covered
/// entries from participating in viewport layout. Overlay also suspends their
/// tickers. The number and order of tabs must remain stable.
class RetainedTabView extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const RetainedTabView({super.key, required this.index, required this.children})
    : assert(index >= 0 && index < children.length);

  @override
  State<RetainedTabView> createState() => _RetainedTabViewState();
}

class _RetainedTab {
  Widget child;
  _TabViewport? viewport;
  late final OverlayEntry entry;

  _RetainedTab(this.child);
}

class _RetainedTabViewState extends State<RetainedTabView> with SingleTickerProviderStateMixin {
  static const ObsidianPageTransitionsBuilder _pageTransition = ObsidianPageTransitionsBuilder();

  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();
  late final List<_RetainedTab> _tabs;
  late final AnimationController _transition;
  _RetainedTab? _outgoingTab;

  List<OverlayEntry> get _orderedEntries => [
    for (final tab in _tabs)
      if (!identical(tab, _tabs[widget.index]) && !identical(tab, _outgoingTab)) tab.entry,
    if (_outgoingTab != null) _outgoingTab!.entry,
    _tabs[widget.index].entry,
  ];

  @override
  void initState() {
    super.initState();

    _tabs = widget.children.map(_createTab).toList();

    final transition = AnimationController(vsync: this, duration: _pageTransition.transitionDuration, value: 1);
    transition.addStatusListener(_handleTransitionStatus);
    _transition = transition;
  }

  @override
  void didUpdateWidget(covariant RetainedTabView oldWidget) {
    super.didUpdateWidget(oldWidget);

    assert(oldWidget.children.length == widget.children.length);

    if (oldWidget.index == widget.index &&
        List.generate(_tabs.length, (i) => _tabs[i].child == widget.children[i]).every((unchanged) => unchanged)) {
      return;
    }

    final replacing = List.generate(_tabs.length, (i) => !Widget.canUpdate(_tabs[i].child, widget.children[i]));

    if (oldWidget.index != widget.index || replacing.contains(true)) {
      _finishTransition();
    }

    final outgoing = _tabs[oldWidget.index];
    final animate = replacing[widget.index];
    final overlay = _overlayKey.currentState!;

    for (var i = 0; i < _tabs.length; i++) {
      final previous = _tabs[i];

      if (replacing[i]) {
        final replacement = _createTab(widget.children[i]);

        replacement.viewport = previous.viewport;
        _tabs[i] = replacement;
        overlay.insert(replacement.entry);

        if (!animate || !identical(previous, outgoing)) {
          previous.entry.remove();
          previous.entry.dispose();
        }
      } else {
        previous.child = widget.children[i];
      }
    }

    if (animate) {
      _outgoingTab = outgoing;
      outgoing.entry.opaque = true;
      _tabs[widget.index].entry.opaque = false;

      _transition.forward(from: 0);

      outgoing.entry.markNeedsBuild();
    }

    for (final tab in _tabs) {
      tab.entry.markNeedsBuild();
    }

    overlay.rearrange(_orderedEntries);
  }

  @override
  void dispose() {
    _transition.dispose();

    final tabs = {..._tabs, if (_outgoingTab != null) _outgoingTab!};

    for (final tab in tabs) {
      tab.entry.remove();
      tab.entry.dispose();
    }

    super.dispose();
  }

  void _handleTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finishTransition();
    }
  }

  _RetainedTab _createTab(Widget child) {
    final tab = _RetainedTab(child);
    tab.entry = OverlayEntry(
      opaque: true,
      maintainState: true,
      builder: (context) {
        final viewport = tab.viewport!;
        final active = identical(tab, _tabs[widget.index]);
        final outgoing = identical(tab, _outgoingTab);

        final content = MediaQuery(
          data: viewport.media,
          child: Theme(
            data: viewport.theme,
            child: ObsidianScale(
              scale: viewport.scale,
              child: PlaybackContentInset(
                top: viewport.topInset,
                bottom: viewport.playbackInset,
                child: ExcludeFocus(
                  excluding: !active,
                  child: IgnorePointer(
                    ignoring: !active,
                    child: RepaintBoundary(child: tab.child),
                  ),
                ),
              ),
            ),
          ),
        );

        // Animate only the visible old and new stacks. Initial routes in the
        // replacement navigator are already settled, including its artist.
        return _pageTransition.buildTransitions<void>(
          null,
          context,
          active && _outgoingTab != null ? _transition : kAlwaysCompleteAnimation,
          outgoing ? _transition : kAlwaysDismissedAnimation,
          content,
        );
      },
    );

    return tab;
  }

  void _finishTransition() {
    final outgoing = _outgoingTab;
    if (outgoing == null) {
      return;
    }

    _outgoingTab = null;
    _transition.stop();
    _transition.value = 1;

    if (!_tabs.contains(outgoing)) {
      outgoing.entry.remove();
      outgoing.entry.dispose();
    } else {
      outgoing.entry.markNeedsBuild();
    }

    for (final tab in _tabs) {
      tab.entry.opaque = true;
      tab.entry.markNeedsBuild();
    }

    _overlayKey.currentState!.rearrange(_orderedEntries);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = (
      media: MediaQuery.of(context),
      theme: Theme.of(context),
      scale: ObsidianScale.of(context),
      topInset: PlaybackContentInset.topOf(context),
      playbackInset: PlaybackContentInset.bottomOf(context),
    );

    // Covered overlay entries can still rebuild if they inherit new viewport
    // data. Freeze their metrics until selected, including the player clearance.
    for (final tab in _tabs) {
      tab.viewport ??= viewport;
    }

    final active = _tabs[widget.index];

    if (active.viewport != viewport) {
      active.viewport = viewport;
      active.entry.markNeedsBuild();
    }

    return Overlay(key: _overlayKey, initialEntries: _orderedEntries);
  }
}

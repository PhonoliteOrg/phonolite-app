import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/desktop_playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shell/navigation/app_bottom_navigation.dart';
import 'package:phonolite_app/ui/shell/navigation/app_side_navigation.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

class AdaptiveScaffold extends StatelessWidget {
  static const double _nowPlayingPadding = 22;

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget page;
  final PlaybackState playbackState;
  final VoidCallback onOpenAlbum;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final ShuffleModeChanged onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLike;
  final bool hidePlaybackChrome;

  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.page,
    required this.playbackState,
    required this.onOpenAlbum,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onStop,
    required this.onSeek,
    required this.onSeekPreview,
    required this.onShuffleChanged,
    required this.onToggleRepeat,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onToggleLike,
    this.hidePlaybackChrome = false,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);

    double s(double value) => value * scale;

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final layoutMode = obsidianLayoutModeOf(context);
    final isWide = layoutMode != ObsidianLayoutMode.compact;
    final compactPlayer = layoutMode == ObsidianLayoutMode.narrow;

    final platform = Theme.of(context).platform;
    final touchPlayer = switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
      _ => false,
    };
    final edgeToEdge = platform == TargetPlatform.iOS;
    final topEdgeToEdge = edgeToEdge || platform == TargetPlatform.android;

    final playerWidth = screenWidth - (isWide ? AppSideNavigation.widthFor(context) : 0);
    final desktopLayout = DesktopPlaybackLayout.supports(platform)
        ? DesktopPlaybackLayout.resolve(availableSize: Size(playerWidth, media.size.height - media.padding.vertical))
        : null;
    final nowPlayingHeight = NowPlayingBar.heightForWidth(
      playerWidth,
      compact: compactPlayer,
      touchTargets: touchPlayer,
    );
    final showWideBar = isWide && !hidePlaybackChrome;
    final showMiniBar = !isWide && !hidePlaybackChrome;
    final miniBarHeight = showMiniBar ? NowPlayingMiniBar.heightForWidth(screenWidth) + s(12) : 0.0;
    final playbackInset = showWideBar
        ? desktopLayout?.height ?? nowPlayingHeight + s(_nowPlayingPadding)
        : miniBarHeight;

    final navPad = AppBottomNavigation.height + media.padding.bottom;
    final double navigationInset;

    if (edgeToEdge) {
      navigationInset = isWide ? media.padding.bottom : navPad;
    } else {
      navigationInset = 0;
    }

    final bottomInset = playbackInset + navigationInset;
    // Mobile content scrolls behind the status bar; iOS also extends behind
    // the bottom navigation. Scroll insets keep the initial content clear.
    final pageContent = MediaQuery.removePadding(
      context: context,
      removeTop: topEdgeToEdge,
      removeBottom: true,
      child: SafeArea(
        bottom: false,
        child: PlaybackContentInset(top: topEdgeToEdge ? media.padding.top : 0, bottom: bottomInset, child: page),
      ),
    );

    final nowPlaying = NowPlayingBar(
      state: playbackState,
      onOpenAlbum: onOpenAlbum,
      onPlayPause: onPlayPause,
      onNext: onNext,
      onPrev: onPrev,
      onStop: onStop,
      onSeek: onSeek,
      onSeekPreview: onSeekPreview,
      onShuffleChanged: onShuffleChanged,
      onToggleRepeat: onToggleRepeat,
      onStreamModeChanged: onStreamModeChanged,
      onVolumeChanged: onVolumeChanged,
      onToggleMute: onToggleMute,
      onToggleLike: onToggleLike,
      compact: compactPlayer,
      touchTargets: touchPlayer,
      desktopLayout: desktopLayout,
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            AppSideNavigation(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: pageContent),
                  if (showWideBar)
                    Positioned(left: 0, right: 0, bottom: edgeToEdge ? media.padding.bottom : 0, child: nowPlaying),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(bottom: edgeToEdge ? 0 : navPad, child: pageContent),
          if (showMiniBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: navPad,
              child: NowPlayingMiniBar(
                state: playbackState,
                onOpenAlbum: onOpenAlbum,
                onPlayPause: onPlayPause,
                onNext: onNext,
                onExpand: () => showNowPlayingExpandedSheet(context, onOpenAlbum: onOpenAlbum),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppBottomNavigation(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
            ),
          ),
        ],
      ),
    );
  }
}

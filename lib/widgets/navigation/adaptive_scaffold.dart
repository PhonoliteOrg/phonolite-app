import 'package:flutter/material.dart';

import '../display/now_playing_bar.dart';
import '../layouts/obsidian_scale.dart';
import '../layouts/playback_content_inset.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_glass_surface.dart';
import '../ui/obsidian_widgets.dart';
import '../../entities/app_controller.dart';

const _navigationBackground = Color(0x40000000);
const _navigationBorder = BorderSide(color: ObsidianPalette.border);

class AdaptiveScaffold extends StatelessWidget {
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
    required this.onToggleLike,
    this.hidePlaybackChrome = false,
  });

  static const double _nowPlayingPadding = 22;
  static const double _navBarHeight = 64;
  static const double _wideLayoutWidth = 980;

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
  final VoidCallback onToggleLike;
  final bool hidePlaybackChrome;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    double s(double value) => value * scale;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isWide = screenWidth >= _wideLayoutWidth;
    final edgeToEdge = Theme.of(context).platform == TargetPlatform.iOS;
    final nowPlayingHeight = NowPlayingBar.heightForWidth(screenWidth);
    final showWideBar = isWide && !hidePlaybackChrome;
    final showMiniBar = !isWide && !hidePlaybackChrome;
    final miniBarHeight = showMiniBar
        ? NowPlayingMiniBar.heightForWidth(screenWidth) + s(12)
        : 0.0;
    final playbackInset = showWideBar
        ? nowPlayingHeight + s(_nowPlayingPadding)
        : miniBarHeight;
    final navPad = _navBarHeight + media.padding.bottom;
    final bottomInset =
        playbackInset +
        (edgeToEdge ? (isWide ? media.padding.bottom : navPad) : 0);
    // iOS scrolls through the system areas and behind the bottom navigation.
    // The scroll content reserves clearance instead of cropping its viewport.
    final pageContent = MediaQuery.removePadding(
      context: context,
      removeTop: edgeToEdge,
      removeBottom: true,
      child: SafeArea(
        bottom: false,
        child: PlaybackContentInset(
          top: edgeToEdge ? media.padding.top : 0,
          bottom: bottomInset,
          child: page,
        ),
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
      onToggleLike: onToggleLike,
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: s(64),
              child: Container(
                decoration: const BoxDecoration(
                  color: _navigationBackground,
                  border: Border(right: _navigationBorder),
                ),
                child: SafeArea(
                  top: edgeToEdge,
                  bottom: edgeToEdge,
                  left: edgeToEdge,
                  right: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: s(16)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        for (var i = 0; i < destinations.length; i++) ...[
                          ObsidianNavIcon(
                            icon:
                                destinations[i].selectedIcon ??
                                destinations[i].icon,
                            isSelected: i == selectedIndex,
                            label: destinations[i].label,
                            onTap: () => onDestinationSelected(i),
                          ),
                          SizedBox(height: s(12)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: pageContent),
                  if (showWideBar)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: edgeToEdge ? media.padding.bottom : 0,
                      child: nowPlaying,
                    ),
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
                onExpand: () => showNowPlayingExpandedSheet(
                  context,
                  onOpenAlbum: onOpenAlbum,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomNavBar(
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

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const double _height = 64;

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final navigation = Container(
      height: _height + bottomPad,
      padding: EdgeInsets.only(
        bottom: bottomPad,
        left: padding.left,
        right: padding.right,
      ),
      decoration: const BoxDecoration(
        color: _navigationBackground,
        border: Border(top: _navigationBorder),
      ),
      child: Center(
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: Center(
                  child: ObsidianNavIcon(
                    icon: destinations[i].selectedIcon ?? destinations[i].icon,
                    isSelected: i == selectedIndex,
                    label: destinations[i].label,
                    onTap: () => onDestinationSelected(i),
                    size: 56,
                    iconSize: 40,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Theme.of(context).platform == TargetPlatform.iOS
        ? ObsidianGlassSurface(child: navigation)
        : navigation;
  }
}

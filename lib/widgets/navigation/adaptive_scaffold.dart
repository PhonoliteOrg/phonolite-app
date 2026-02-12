import 'package:flutter/material.dart';

import '../display/now_playing_bar.dart';
import '../layouts/app_scope.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import '../../entities/app_controller.dart';

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.page,
    required this.playbackState,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onStop,
    required this.onSeek,
    required this.onShuffleChanged,
    required this.onToggleRepeat,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleLike,
  });

  static const double _nowPlayingPadding = 22;
  static const double _navBarHeight = 64;

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget page;
  final PlaybackState playbackState;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<ShuffleMode> onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    double s(double value) => value * scale;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isWide = screenWidth >= 900;
    final nowPlayingHeight = NowPlayingBar.heightForWidth(screenWidth);
    final showMiniBar = playbackState.track != null;
    final miniBarHeight = showMiniBar
        ? NowPlayingMiniBar.heightForWidth(screenWidth) + s(12)
        : 0.0;
    final bottomInset =
        isWide ? nowPlayingHeight + s(_nowPlayingPadding) : miniBarHeight;
    final navPad = _navBarHeight + media.padding.bottom;


    final nowPlaying = NowPlayingBar(
      state: playbackState,
      onPlayPause: onPlayPause,
      onNext: onNext,
      onPrev: onPrev,
      onStop: onStop,
      onSeek: onSeek,
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
              width: s(96),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  border: const Border(
                    right: BorderSide(color: Color(0x1FFFFFFF)),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: s(16)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (var i = 0; i < destinations.length; i++) ...[
                        ObsidianNavIcon(
                          icon: destinations[i].selectedIcon ?? destinations[i].icon,
                          isSelected: i == selectedIndex,
                          onTap: () => onDestinationSelected(i),
                        ),
                        SizedBox(height: s(12)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottomInset),
                        child: page,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
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
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset + navPad),
                child: page,
              ),
            ),
          ),
          if (showMiniBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: navPad,
              child: NowPlayingMiniBar(
                state: playbackState,
                onPlayPause: onPlayPause,
                onExpand: () => showNowPlayingExpandedSheet(context),
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
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      height: _height + bottomPad,
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: ObsidianPalette.obsidianElevated.withOpacity(0.92),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
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
                    onTap: () => onDestinationSelected(i),
                    size: 56,
                    iconSize: 36,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

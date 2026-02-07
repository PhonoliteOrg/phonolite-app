import 'package:flutter/material.dart';

import '../display/now_playing_bar.dart';
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

  static const double _nowPlayingHeight = 135;
  static const double _nowPlayingPadding = 22;
  static const double _navBarHeight = 80;

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
    final isWide = MediaQuery.of(context).size.width >= 900;
    final bottomInset = _nowPlayingHeight + _nowPlayingPadding;
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
              width: 96,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  border: const Border(
                    right: BorderSide(color: Color(0x1FFFFFFF)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (var i = 0; i < destinations.length; i++) ...[
                        _SidebarTabButton(
                          icon: destinations[i].selectedIcon ?? destinations[i].icon,
                          isActive: i == selectedIndex,
                          onTap: () => onDestinationSelected(i),
                        ),
                        const SizedBox(height: 12),
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
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: page,
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
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset + _navBarHeight),
              child: page,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _navBarHeight,
            child: nowPlaying,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    );
  }
}

class _SidebarTabButton extends StatefulWidget {
  const _SidebarTabButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final Widget icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_SidebarTabButton> createState() => _SidebarTabButtonState();
}

class _SidebarTabButtonState extends State<_SidebarTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final fill = isActive
        ? ObsidianPalette.gold.withOpacity(0.1)
        : Colors.white.withOpacity(0.03);
    final border = isActive
        ? ObsidianPalette.gold
        : _hovered
            ? Colors.grey.shade300.withOpacity(0.8)
            : Colors.white.withOpacity(0.05);
    final iconColor = isActive
        ? ObsidianPalette.gold
        : _hovered
            ? Colors.grey.shade300.withOpacity(0.9)
            : ObsidianPalette.textMuted;
    final shadow = [
      BoxShadow(
        color: isActive
            ? ObsidianPalette.goldSoft
            : _hovered
                ? Colors.grey.shade300.withOpacity(0.25)
                : Colors.transparent,
        blurRadius: isActive || _hovered ? 12 : 0,
      ),
    ];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ClipPath(
        clipper: const CutTopLeftBottomRightClipper(cut: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            boxShadow: shadow,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Center(
                child: TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 200),
                  tween: ColorTween(end: iconColor),
                  curve: Curves.easeOut,
                  builder: (context, color, child) => IconTheme(
                    data: IconThemeData(color: color),
                    child: child!,
                  ),
                  child: widget.icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

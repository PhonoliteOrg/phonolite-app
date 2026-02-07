import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/navigation/adaptive_scaffold.dart';
import 'library_page.dart';
import 'liked_page.dart';
import 'messages_page.dart';
import 'playlists_page.dart';
import 'stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final pages = <Widget>[
      _buildTabNavigator(0, const LibraryPage()),
      _buildTabNavigator(1, const PlaylistsPage()),
      _buildTabNavigator(2, const LikedPage()),
      _buildTabNavigator(3, const StatsPage()),
      _buildTabNavigator(4, const MessagesPage()),
    ];

    return WillPopScope(
      onWillPop: () async {
        final navigator = _navigatorKeys[_selectedIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
          return false;
        }
        return true;
      },
      child: StreamBuilder<PlaybackState>(
        stream: controller.playbackStream,
        initialData: controller.playbackState,
        builder: (context, snapshot) {
          final playback = snapshot.data ?? controller.playbackState;
          return AdaptiveScaffold(
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.library_music), label: 'Library'),
              NavigationDestination(
                  icon: Icon(Icons.queue_music), label: 'Playlists'),
              NavigationDestination(icon: Icon(Icons.favorite), label: 'Liked'),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
              NavigationDestination(icon: Icon(Icons.message), label: 'Messages'),
            ],
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            page: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
            playbackState: playback,
            onPlayPause: () => controller.pause(playback.isPlaying),
            onNext: controller.nextTrack,
            onPrev: controller.prevTrack,
            onStop: controller.stop,
            onSeek: controller.seekTo,
            onShuffleChanged: controller.updateShuffleMode,
            onToggleRepeat: controller.toggleRepeatMode,
            onStreamModeChanged: controller.updateStreamMode,
            onVolumeChanged: controller.setVolume,
            onToggleLike: () {
              final track = playback.track;
              if (track != null) {
                controller.toggleLike(track);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => child,
      ),
    );
  }
}

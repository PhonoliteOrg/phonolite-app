import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/display/now_playing_bar.dart';
import '../widgets/navigation/adaptive_scaffold.dart';
import 'library_page.dart';
import 'liked_page.dart';
import 'settings_page.dart';
import 'playlists_page.dart';
import 'stats_page.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(5, (_) => GlobalKey<NavigatorState>());
  bool _nowPlayingSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    final controller = AppScope.of(context);
    controller.handleAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final pages = <Widget>[
      _buildTabNavigator(0, const LibraryPage()),
      _buildTabNavigator(1, const PlaylistsPage()),
      _buildTabNavigator(2, const LikedPage()),
      _buildTabNavigator(3, const StatsPage()),
      _buildTabNavigator(4, const SettingsPage()),
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
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
            ],
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            page: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
            playbackState: playback,
            onOpenAlbum: _openCurrentAlbum,
            onPlayPause: () => controller.pause(playback.isPlaying),
            onNext: controller.nextTrack,
            onPrev: controller.prevTrack,
            onStop: controller.stop,
            onSeek: controller.seekTo,
            onSeekPreview: controller.previewSeek,
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

  void _openCurrentAlbum() {
    () async {
      final controller = AppScope.of(context);
      final track = controller.playbackState.track;
      final albumId = track?.albumId;
      if (track == null || albumId == null || albumId.isEmpty) {
        return;
      }
      try {
        final album = await controller.connection.fetchAlbumById(albumId);
        final artist = await controller.connection.fetchArtistById(album.artistId);
        if (!mounted) {
          return;
        }
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
        final navigator = _navigatorKeys[0].currentState;
        if (navigator == null) {
          return;
        }
        navigator.popUntil((route) => route.isFirst);
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(artist: artist),
          ),
        );
        navigator.push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              album: album,
              artistName: album.artist.isNotEmpty ? album.artist : track.artist,
            ),
          ),
        );
      } catch (_) {
        try {
          final album = await controller.connection.fetchAlbumById(albumId);
          if (!mounted) {
            return;
          }
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
          }
          final navigator = _navigatorKeys[0].currentState;
          if (navigator == null) {
            return;
          }
          navigator.popUntil((route) => route.isFirst);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(
                album: album,
                artistName: album.artist.isNotEmpty ? album.artist : track.artist,
              ),
            ),
          );
        } catch (_) {}
      }
    }();
  }
}

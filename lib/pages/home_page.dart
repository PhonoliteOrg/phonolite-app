import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../entities/app_controller.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/navigation/adaptive_scaffold.dart';
import 'library_page.dart';
import 'liked_page.dart';
import 'settings_page.dart';
import 'playlists_page.dart';
import 'stats_page.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );
  final List<String?> _topRouteNames = List.filled(5, null);
  late final List<NavigatorObserver> _routeObservers;

  @override
  void initState() {
    super.initState();
    _routeObservers = List.generate(
      _navigatorKeys.length,
      (index) => _TabRouteObserver(
        onRouteChanged: (routeName) => _setTopRouteName(index, routeName),
      ),
    );
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
                icon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music),
                label: 'Playlists',
              ),
              NavigationDestination(icon: Icon(Icons.favorite), label: 'Liked'),
              NavigationDestination(
                icon: Icon(Icons.bar_chart),
                label: 'Stats',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            page: IndexedStack(index: _selectedIndex, children: pages),
            hidePlaybackChrome:
                _topRouteNames[_selectedIndex] == LoginPage.routeName,
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
                if (playback.isLocalPlayback ||
                    playback.queueSource == PlaybackQueueSource.offline) {
                  controller.toggleLocalLike(track);
                } else {
                  controller.toggleLike(track);
                }
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
      observers: [_routeObservers[index]],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(settings: settings, builder: (_) => child),
    );
  }

  void _setTopRouteName(int index, String? routeName) {
    if (_topRouteNames[index] == routeName) {
      return;
    }
    void updateRouteName() {
      if (!mounted || _topRouteNames[index] == routeName) {
        return;
      }
      setState(() => _topRouteNames[index] = routeName);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => updateRouteName());
      return;
    }
    updateRouteName();
  }

  void _openCurrentAlbum() {
    () async {
      final controller = AppScope.of(context);
      final track = controller.playbackState.track;
      final albumId = track?.albumId;
      if (track == null ||
          albumId == null ||
          albumId.isEmpty ||
          controller.playbackState.isLocalPlayback ||
          !controller.authState.isAuthorized) {
        return;
      }
      try {
        final album = await controller.connection.fetchAlbumById(albumId);
        final artist = await controller.connection.fetchArtistById(
          album.artistId,
        );
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
          MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)),
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
                artistName: album.artist.isNotEmpty
                    ? album.artist
                    : track.artist,
              ),
            ),
          );
        } catch (_) {}
      }
    }();
  }
}

class _TabRouteObserver extends NavigatorObserver {
  _TabRouteObserver({required this.onRouteChanged});

  final ValueChanged<String?> onRouteChanged;

  void _notify(String? routeName) {
    onRouteChanged(routeName);
  }

  void _notifyAfterTransition(
    Route<dynamic>? transitionRoute,
    String? routeName,
    AnimationStatus targetStatus,
  ) {
    final animation = transitionRoute is TransitionRoute<dynamic>
        ? transitionRoute.animation
        : null;
    if (animation == null || animation.status == targetStatus) {
      _notify(routeName);
      return;
    }

    late AnimationStatusListener listener;
    listener = (status) {
      if (status != targetStatus) {
        return;
      }
      animation.removeStatusListener(listener);
      _notify(routeName);
    };
    animation.addStatusListener(listener);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyAfterTransition(
      route,
      route.settings.name,
      AnimationStatus.completed,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyAfterTransition(
      route,
      previousRoute?.settings.name,
      AnimationStatus.dismissed,
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _notifyAfterTransition(
      newRoute,
      newRoute?.settings.name,
      AnimationStatus.completed,
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute?.settings.name);
  }
}

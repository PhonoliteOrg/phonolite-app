import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';
import '../widgets/ui/playlist_icon.dart';
import '../widgets/ui/stats_icon.dart';
import 'package:flutter/scheduler.dart';

import '../entities/app_controller.dart';
import '../entities/local_library_selection.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/retained_tab_view.dart';
import '../widgets/navigation/adaptive_scaffold.dart';
import 'library_page.dart';
import 'liked_page.dart';
import 'settings_page.dart';
import 'playlists_page.dart';
import 'playlist_detail_view.dart';
import 'stats_page.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'local_album_detail_screen.dart';
import 'local_artist_detail_screen.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  AppController? _controller;
  StreamSubscription<bool>? _statsCollectionSubscription;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );
  final List<String?> _topRouteNames = List.filled(5, null);
  late final List<NavigatorObserver> _routeObservers;
  late final List<Widget> _pages;
  final _tabViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _routeObservers = List.generate(
      _navigatorKeys.length,
      (index) => _TabRouteObserver(
        onRouteChanged: (routeName) => _setTopRouteName(index, routeName),
      ),
    );
    _pages = <Widget>[
      _buildTabNavigator(0, const LibraryPage()),
      _buildTabNavigator(1, const PlaylistsPage()),
      _buildTabNavigator(2, const LikedPage()),
      _buildTabNavigator(3, const StatsPage()),
      _buildTabNavigator(4, const SettingsPage()),
    ];
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (identical(controller, _controller)) {
      return;
    }
    _statsCollectionSubscription?.cancel();
    _controller = controller;
    if (!controller.statsCollectionEnabled && _selectedIndex == 3) {
      _selectedIndex = 0;
    }
    _statsCollectionSubscription = controller.statsCollectionEnabledStream
        .distinct()
        .listen((enabled) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (!enabled && _selectedIndex == 3) {
              _selectedIndex = 0;
            }
          });
        });
  }

  @override
  void dispose() {
    _statsCollectionSubscription?.cancel();
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
    final statsEnabled = controller.statsCollectionEnabled;
    // Keep the retained navigators stable while Stats is hidden from navigation.
    final visibleTabIndices = [0, 1, 2, if (statsEnabled) 3, 4];
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
            destinations: [
              const NavigationDestination(
                icon: Icon(PhonoliteIcons.disc3),
                label: 'Library',
              ),
              const NavigationDestination(
                icon: PlaylistIcon(),
                label: 'Playlists',
              ),
              const NavigationDestination(
                icon: Icon(PhonoliteIcons.heart),
                label: 'Liked',
              ),
              if (statsEnabled)
                const NavigationDestination(icon: StatsIcon(), label: 'Stats'),
              const NavigationDestination(
                icon: Icon(PhonoliteIcons.settings),
                label: 'Settings',
              ),
            ],
            selectedIndex: visibleTabIndices.indexOf(_selectedIndex),
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = visibleTabIndices[index]),
            page: RetainedTabView(
              key: _tabViewKey,
              index: _selectedIndex,
              children: _pages,
            ),
            hidePlaybackChrome:
                _topRouteNames[_selectedIndex] == LoginPage.routeName,
            playbackState: playback,
            onOpenAlbum: _openCurrentPlaybackDetails,
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

  void _openCurrentPlaybackDetails() {
    () async {
      final controller = AppScope.of(context);
      final playback = controller.playbackState;
      final track = playback.track;
      if (track == null) {
        return;
      }
      if (playback.hasPlaylistSource) {
        if (_selectedIndex != 1) {
          setState(() => _selectedIndex = 1);
        }
        final navigator = _navigatorKeys[1].currentState;
        if (navigator == null) {
          return;
        }
        navigator.popUntil((route) => route.isFirst);
        navigator.push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailView(
              playlistId: playback.queueSourcePlaylistId!,
              isLocal: playback.queueSource == PlaybackQueueSource.offline,
            ),
          ),
        );
        return;
      }
      if (playback.isLocalPlayback ||
          playback.queueSource == PlaybackQueueSource.offline) {
        final snapshot = controller.offlineLibrarySnapshot;
        final selection = LocalLibrarySelection(
          tracks: snapshot.tracks,
          artists: snapshot.artistGroups,
        );
        final album = selection.albumForTrack(track);
        if (album == null) {
          return;
        }
        final artist =
            selection.artist(album.artistId) ?? selection.artistForTrack(track);
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
        final navigator = _navigatorKeys[0].currentState;
        if (navigator == null) {
          return;
        }
        navigator.popUntil((route) => route.isFirst);
        if (artist != null) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => LocalArtistDetailScreen(group: artist),
            ),
          );
        }
        navigator.push(
          MaterialPageRoute(
            builder: (_) => LocalAlbumDetailScreen(album: album),
          ),
        );
        return;
      }
      final albumId = track.albumId;
      if (albumId == null ||
          albumId.isEmpty ||
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

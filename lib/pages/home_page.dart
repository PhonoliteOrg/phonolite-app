import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/ui/phonolite_icons.dart';
import '../widgets/ui/playlist_icon.dart';
import '../widgets/ui/stats_icon.dart';
import 'package:flutter/scheduler.dart';

import '../entities/app_controller.dart';
import '../entities/local_library_selection.dart';
import '../entities/models.dart';
import '../entities/offline_library_views.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/layouts/retained_tab_view.dart';
import '../widgets/navigation/adaptive_scaffold.dart';
import '../widgets/navigation/desktop_mouse_navigation.dart';
import '../widgets/navigation/menu_navigation_history.dart';
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
import 'reset_user_password_page.dart';

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
  late final List<_TabRouteObserver> _routeObservers;
  late List<Widget> _pages;
  final _tabViewKey = GlobalKey();
  bool _openingPlaybackDetails = false;
  bool _openingStatsDetails = false;

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
      _buildTabNavigator(
        3,
        StatsPage(onArtistTap: _openStatsArtist, onTrackTap: _openStatsTrack),
      ),
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
    return DesktopMouseNavigation(
      onBack: () => _routeObservers[_selectedIndex].goBack(),
      onForward: () => _routeObservers[_selectedIndex].goForward(),
      child: WillPopScope(
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
                  const NavigationDestination(
                    icon: StatsIcon(),
                    label: 'Stats',
                  ),
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
                  _topRouteNames[_selectedIndex] == LoginPage.routeName ||
                  _topRouteNames[_selectedIndex] ==
                      ResetUserPasswordPage.routeName,
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
      ),
    );
  }

  Widget _buildTabNavigator(
    int index,
    Widget child, {
    List<MaterialPageRoute<void> Function()> initialRoutes = const [],
  }) {
    return Navigator(
      key: _navigatorKeys[index],
      observers: [_routeObservers[index]],
      onGenerateInitialRoutes: initialRoutes.isEmpty
          ? Navigator.defaultGenerateInitialRoutes
          : (_, _) => [
              MaterialPageRoute<void>(builder: (_) => child),
              for (final createRoute in initialRoutes) createRoute(),
            ],
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

  bool _pushDetails(
    int tabIndex,
    int sourceTabIndex,
    String routeName,
    WidgetBuilder builder, {
    MaterialPageRoute<void>? parentRoute,
  }) {
    final navigator = _navigatorKeys[tabIndex].currentState;
    if (!mounted ||
        navigator == null ||
        !navigator.mounted ||
        _selectedIndex != sourceTabIndex) {
      return false;
    }
    final currentRouteName = _routeObservers[tabIndex].currentRouteName;
    if (_selectedIndex == tabIndex && currentRouteName == routeName) {
      return true;
    }
    MaterialPageRoute<void> destination() => MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: builder,
    );
    if (_selectedIndex == tabIndex &&
        parentRoute != null &&
        currentRouteName == parentRoute.settings.name) {
      unawaited(navigator.push<void>(destination()));
      return true;
    }

    // Install the whole destination hierarchy together. RetainedTabView
    // transitions from the visible screen to the settled destination.
    setState(() {
      _navigatorKeys[tabIndex] = GlobalKey<NavigatorState>();
      _routeObservers[tabIndex] = _TabRouteObserver(
        onRouteChanged: (name) => _setTopRouteName(tabIndex, name),
      )..currentRouteName = routeName;
      _topRouteNames[tabIndex] = routeName;
      _pages = List.of(_pages);
      _pages[tabIndex] = _buildTabNavigator(
        tabIndex,
        tabIndex == 0 ? const LibraryPage() : const PlaylistsPage(),
        initialRoutes: [
          if (parentRoute != null) () => parentRoute,
          destination,
        ],
      );
      _selectedIndex = tabIndex;
    });
    return true;
  }

  Future<bool> _openLibraryTrackDetails(
    AppController controller,
    Track track, {
    required bool isLocal,
    required int sourceTabIndex,
    LocalLibrarySelection? localSelection,
  }) async {
    if (isLocal) {
      final snapshot = controller.offlineLibrarySnapshot;
      final selection =
          localSelection ??
          LocalLibrarySelection(
            tracks: snapshot.tracks,
            artists: snapshot.artistGroups,
          );
      final album = selection.albumForTrack(track);
      if (album == null) return false;
      final artist =
          selection.artist(album.artistId) ?? selection.artistForTrack(track);
      if (artist == null) return false;
      return _pushDetails(
        0,
        sourceTabIndex,
        LocalAlbumDetailScreen.routeNameFor(album.id),
        (_) => LocalAlbumDetailScreen(album: album),
        parentRoute: MaterialPageRoute<void>(
          settings: RouteSettings(
            name: LocalArtistDetailScreen.routeNameFor(artist.id),
          ),
          builder: (_) => LocalArtistDetailScreen(group: artist),
        ),
      );
    }

    final albumId = track.albumId;
    if (albumId == null ||
        albumId.isEmpty ||
        !controller.authState.isAuthorized) {
      return false;
    }
    final server = controller.connection.baseUrl;
    final album = await controller.connection.fetchAlbumById(albumId);
    if (!mounted ||
        !identical(controller, _controller) ||
        controller.connection.baseUrl != server ||
        !controller.authState.isAuthorized) {
      return false;
    }
    final artistName = album.artist.isNotEmpty ? album.artist : track.artist;
    // The artist page refreshes its metadata and releases when built.
    final artist = Artist(id: album.artistId, name: artistName, albumCount: 0);
    return _pushDetails(
      0,
      sourceTabIndex,
      AlbumDetailScreen.routeNameFor(album.id),
      (_) => AlbumDetailScreen(album: album, artistName: artistName),
      parentRoute: MaterialPageRoute<void>(
        settings: RouteSettings(
          name: ArtistDetailScreen.routeNameFor(artist.id),
        ),
        builder: (_) => ArtistDetailScreen(artist: artist),
      ),
    );
  }

  Future<void> _openCurrentPlaybackDetails() async {
    if (_openingPlaybackDetails) return;
    final controller = AppScope.of(context);
    final playback = controller.playbackState;
    final track = playback.track;
    final sourceTabIndex = _selectedIndex;
    if (track == null) return;

    _openingPlaybackDetails = true;
    try {
      if (playback.hasPlaylistSource) {
        final isLocal = playback.queueSource == PlaybackQueueSource.offline;
        _pushDetails(
          1,
          sourceTabIndex,
          '/playback/${isLocal ? 'local' : 'server'}/playlist/${playback.queueSourcePlaylistId}',
          (_) => PlaylistDetailView(
            playlistId: playback.queueSourcePlaylistId!,
            isLocal: isLocal,
          ),
        );
        return;
      }
      await _openLibraryTrackDetails(
        controller,
        track,
        isLocal:
            playback.isLocalPlayback ||
            playback.queueSource == PlaybackQueueSource.offline,
        sourceTabIndex: sourceTabIndex,
      );
    } catch (_) {
      // Metadata may be unavailable if the server disconnects.
    } finally {
      _openingPlaybackDetails = false;
    }
  }

  LocalLibrarySelection _statsLocalSelection(AppController controller) {
    final snapshot = controller.offlineLibrarySnapshot;
    if (!controller.authState.hasSession) {
      return LocalLibrarySelection(
        tracks: snapshot.tracks,
        artists: snapshot.artistGroups,
      );
    }
    // Account statistics must not resolve an ID against another server's copy.
    final tracks = snapshot.tracks
        .where((track) => track.serverBaseUrl == controller.connection.baseUrl)
        .toList();
    return LocalLibrarySelection(
      tracks: tracks,
      artists: offlineArtistGroups(tracks),
    );
  }

  Future<void> _openStatsArtist(StatsItem item) async {
    if (_openingStatsDetails || item.id.trim().isEmpty) return;
    _openingStatsDetails = true;
    final controller = AppScope.of(context);
    final sourceTabIndex = _selectedIndex;
    final server = controller.connection.baseUrl;
    final hasSession = controller.authState.hasSession;
    bool current() =>
        mounted &&
        identical(controller, _controller) &&
        _selectedIndex == sourceTabIndex &&
        controller.connection.baseUrl == server &&
        controller.authState.hasSession == hasSession;
    try {
      if (controller.authState.isAuthorized) {
        try {
          final artist = await controller.connection.fetchArtistById(item.id);
          if (!current()) return;
          if (controller.authState.isAuthorized) {
            _pushDetails(
              0,
              sourceTabIndex,
              ArtistDetailScreen.routeNameFor(artist.id),
              (_) => ArtistDetailScreen(artist: artist),
            );
            return;
          }
        } catch (_) {
          // Downloaded metadata can still provide a destination while offline.
        }
      }
      if (!current()) return;
      final selection = _statsLocalSelection(controller);
      // Legacy statistics use the display name when no artist ID was known.
      final artist =
          selection.artist(item.id) ??
          (item.id == item.name
              ? selection.artist(item.name.trim().toLowerCase())
              : null);
      if (artist != null) {
        _pushDetails(
          0,
          sourceTabIndex,
          LocalArtistDetailScreen.routeNameFor(artist.id),
          (_) => LocalArtistDetailScreen(group: artist),
        );
      } else {
        _showStatsDestinationUnavailable('artist');
      }
    } finally {
      _openingStatsDetails = false;
    }
  }

  Future<void> _openStatsTrack(StatsTrack item) async {
    if (_openingStatsDetails || item.id.trim().isEmpty) return;
    _openingStatsDetails = true;
    final controller = AppScope.of(context);
    final sourceTabIndex = _selectedIndex;
    final server = controller.connection.baseUrl;
    final hasSession = controller.authState.hasSession;
    bool current() =>
        mounted &&
        identical(controller, _controller) &&
        _selectedIndex == sourceTabIndex &&
        controller.connection.baseUrl == server &&
        controller.authState.hasSession == hasSession;
    try {
      if (controller.authState.isAuthorized) {
        try {
          final track = await controller.connection.fetchTrackById(item.id);
          if (!current()) return;
          if (await _openLibraryTrackDetails(
            controller,
            track,
            isLocal: false,
            sourceTabIndex: sourceTabIndex,
          )) {
            return;
          }
        } catch (_) {
          // Fall back to this catalog's downloaded track, when available.
        }
      }
      if (!current()) return;
      final selection = _statsLocalSelection(controller);
      final track = selection.track(item.id);
      if (track != null &&
          await _openLibraryTrackDetails(
            controller,
            track,
            isLocal: true,
            sourceTabIndex: sourceTabIndex,
            localSelection: selection,
          )) {
        return;
      }
      if (current()) _showStatsDestinationUnavailable('track');
    } finally {
      _openingStatsDetails = false;
    }
  }

  void _showStatsDestinationUnavailable(String kind) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('This $kind is not available in the library.')),
    );
  }
}

class _TabRouteObserver extends MenuNavigationHistory {
  _TabRouteObserver({required this.onRouteChanged});

  final ValueChanged<String?> onRouteChanged;
  String? currentRouteName;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    currentRouteName = topRoute.settings.name;
  }

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
    super.didPush(route, previousRoute);
    _notifyAfterTransition(
      route,
      route.settings.name,
      AnimationStatus.completed,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _notifyAfterTransition(
      route,
      previousRoute?.settings.name,
      AnimationStatus.dismissed,
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _notifyAfterTransition(
      newRoute,
      newRoute?.settings.name,
      AnimationStatus.completed,
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _notify(previousRoute?.settings.name);
  }
}

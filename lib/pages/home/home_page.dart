import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_navigation_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/pages/auth/login_page.dart';
import 'package:phonolite_app/pages/auth/reset_user_password_page.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/pages/library/artist_detail_screen.dart';
import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/pages/listening_stats/stats_page.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/pages/settings/settings_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/navigation/desktop_mouse_navigation.dart';
import 'package:phonolite_app/ui/navigation/live_pop_scope.dart';
import 'package:phonolite_app/ui/navigation/retained_tab_view.dart';
import 'package:phonolite_app/ui/navigation/tab_route_observer.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/stats_icon.dart';
import 'package:phonolite_app/ui/shell/adaptive_scaffold.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';

class HomePage extends BasePage {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends BasePageState<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  AppController? _controller;
  LibraryNavigationController? _navigation;
  StreamSubscription<bool>? _statsCollectionSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _openingSignIn = false;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final List<String?> _topRouteNames = List.filled(5, null);
  final ValueNotifier<int> _tabBackChanges = ValueNotifier(0);
  late final List<TabRouteObserver> _routeObservers;
  late List<Widget> _pages;
  final GlobalKey<State<StatefulWidget>> _tabViewKey = GlobalKey();
  bool _openingPlaybackDetails = false;
  bool _openingStatsDetails = false;

  @override
  void initState() {
    super.initState();

    _routeObservers = List.generate(
      _navigatorKeys.length,
      (index) => TabRouteObserver(onRouteChanged: (routeName) => _setTopRouteName(index, routeName)),
    );

    _pages = <Widget>[
      _buildTabNavigator(0, const LibraryPage()),
      _buildTabNavigator(1, const PlaylistsPage()),
      _buildTabNavigator(2, const LikedPage()),
      _buildTabNavigator(3, StatsPage(onArtistTap: _openStatsArtist, onTrackTap: _openStatsTrack)),
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
    _authSubscription?.cancel();
    _controller = controller;

    _navigation?.dispose();

    _navigation = LibraryNavigationController(controller);
    _authSubscription = controller.authStream.listen(_handleAuthState);
    _handleAuthState(controller.authState);

    if (!controller.statsCollectionEnabled && _selectedIndex == 3) {
      _selectedIndex = 0;
    }

    _statsCollectionSubscription = controller.statsCollectionEnabledStream.distinct().listen(
      _handleStatsCollectionChanged,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }

    final controller = AppScope.of(context);

    controller.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    _statsCollectionSubscription?.cancel();
    _authSubscription?.cancel();

    _navigation?.dispose();
    _tabBackChanges.dispose();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void _handleStatsCollectionChanged(bool enabled) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (!enabled && _selectedIndex == 3) {
        _selectedIndex = 0;
      }
    });
  }

  void _handleAuthState(AuthState state) {
    if (!state.requiresSignIn || _openingSignIn || !mounted) {
      return;
    }

    _openingSignIn = true;
    WidgetsBinding.instance.addPostFrameCallback(_openRequiredSignIn);
  }

  Future<void> _openRequiredSignIn(Duration timeStamp) async {
    final controller = _controller;

    if (!mounted || controller == null || !controller.authState.requiresSignIn) {
      _openingSignIn = false;

      return;
    }

    // A sign-in page may already be open inside a retained tab.
    final loginTab = _topRouteNames.indexOf(LoginPage.routeName);

    if (loginTab >= 0) {
      setState(() => _selectedIndex = loginTab);
      _openingSignIn = false;

      return;
    }

    try {
      setState(() => _selectedIndex = 4);

      await _navigatorKeys[4].currentState!.push(LoginPage.route(controller));
    } finally {
      _openingSignIn = false;
    }
  }

  Widget _buildTabNavigator(
    int index,
    Widget child, {
    List<MaterialPageRoute<void> Function()> initialRoutes = const [],
  }) {
    final navigatorKey = _navigatorKeys[index];
    final root = _TabRootBackObserver(onChanged: () => _updateTabBackHandling(index, navigatorKey), child: child);

    return NotificationListener<NavigationNotification>(
      key: ValueKey(navigatorKey),
      onNotification: (_) => _updateTabBackHandling(index, navigatorKey),
      child: Navigator(
        key: navigatorKey,
        observers: [_routeObservers[index]],
        onGenerateInitialRoutes: initialRoutes.isEmpty
            ? Navigator.defaultGenerateInitialRoutes
            : (_, _) => [
                MaterialPageRoute<void>(builder: (_) => root),
                for (final createRoute in initialRoutes) createRoute(),
              ],
        onGenerateRoute: (settings) => MaterialPageRoute(settings: settings, builder: (_) => root),
      ),
    );
  }

  bool _updateTabBackHandling(int index, GlobalKey<NavigatorState> navigatorKey) {
    if (mounted && identical(navigatorKey, _navigatorKeys[index])) {
      _tabBackChanges.value += 1;
    }

    // Only the selected tab determines whether Home intercepts system back.
    // Replaced and inactive navigator notifications must not reach the app root.
    return true;
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

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
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

    if (!mounted || navigator == null || !navigator.mounted || _selectedIndex != sourceTabIndex) {
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

    if (_selectedIndex == tabIndex && parentRoute != null && currentRouteName == parentRoute.settings.name) {
      unawaited(navigator.push<void>(destination()));

      return true;
    }

    // Install the whole destination hierarchy together. RetainedTabView
    // transitions from the visible screen to the settled destination.
    setState(() {
      _navigatorKeys[tabIndex] = GlobalKey<NavigatorState>();

      final routeObserver = TabRouteObserver(onRouteChanged: (name) => _setTopRouteName(tabIndex, name));

      routeObserver.currentRouteName = routeName;
      _routeObservers[tabIndex] = routeObserver;
      _topRouteNames[tabIndex] = routeName;

      _pages = List.of(_pages);
      _pages[tabIndex] = _buildTabNavigator(
        tabIndex,
        tabIndex == 0 ? const LibraryPage() : const PlaylistsPage(),
        initialRoutes: [if (parentRoute != null) () => parentRoute, destination],
      );

      _selectedIndex = tabIndex;
    });

    return true;
  }

  bool _showLibraryDestination(LibraryDestination destination, int sourceTabIndex) {
    final localAlbum = destination.localAlbum;
    final localArtist = destination.localArtist;

    if (localAlbum != null && localArtist != null) {
      return _pushDetails(
        0,
        sourceTabIndex,
        LocalAlbumDetailScreen.routeNameFor(localAlbum.id),
        (_) => LocalAlbumDetailScreen(album: localAlbum),
        parentRoute: MaterialPageRoute<void>(
          settings: RouteSettings(name: LocalArtistDetailScreen.routeNameFor(localArtist.id)),
          builder: (_) => LocalArtistDetailScreen(group: localArtist),
        ),
      );
    }

    if (localArtist != null) {
      return _pushDetails(
        0,
        sourceTabIndex,
        LocalArtistDetailScreen.routeNameFor(localArtist.id),
        (_) => LocalArtistDetailScreen(group: localArtist),
      );
    }

    final artist = destination.artist;
    final album = destination.album;

    if (album != null && artist != null) {
      return _pushDetails(
        0,
        sourceTabIndex,
        AlbumDetailScreen.routeNameFor(album.id),
        (_) => AlbumDetailScreen(album: album, artistName: destination.artistName),
        parentRoute: MaterialPageRoute<void>(
          settings: RouteSettings(name: ArtistDetailScreen.routeNameFor(artist.id)),
          builder: (_) => ArtistDetailScreen(artist: artist),
        ),
      );
    }

    if (artist != null) {
      return _pushDetails(
        0,
        sourceTabIndex,
        ArtistDetailScreen.routeNameFor(artist.id),
        (_) => ArtistDetailScreen(artist: artist),
      );
    }

    return false;
  }

  Future<bool> _openLibraryTrackDetails(Track track, {required bool isLocal, required int sourceTabIndex}) async {
    final navigation = _navigation!;

    final destination = await navigation.track(track, local: isLocal);

    if (!mounted || !identical(navigation, _navigation) || destination == null) {
      return false;
    }

    return _showLibraryDestination(destination, sourceTabIndex);
  }

  Future<void> _openStatsArtist(StatsItem item) =>
      _openStatsDestination('artist', item.id, () => _navigation!.statsArtist(item));

  Future<void> _openStatsTrack(StatsTrack item) =>
      _openStatsDestination('track', item.id, () => _navigation!.statsTrack(item));

  Future<void> _openStatsDestination(String kind, String id, Future<LibraryDestination?> Function() resolve) async {
    if (_openingStatsDetails || id.trim().isEmpty) {
      return;
    }

    _openingStatsDetails = true;

    final navigation = _navigation;
    final sourceTabIndex = _selectedIndex;

    try {
      final destination = await resolve();

      if (!mounted || !identical(navigation, _navigation) || _selectedIndex != sourceTabIndex) {
        return;
      }

      if (destination == null || !_showLibraryDestination(destination, sourceTabIndex)) {
        _showStatsDestinationUnavailable(kind);
      }
    } finally {
      _openingStatsDetails = false;
    }
  }

  Future<void> _openCurrentPlaybackDetails() async {
    if (_openingPlaybackDetails) {
      return;
    }

    final controller = AppScope.of(context);
    final playback = controller.playbackState;
    final track = playback.track;
    final sourceTabIndex = _selectedIndex;

    if (track == null) {
      return;
    }

    _openingPlaybackDetails = true;

    try {
      if (playback.hasPlaylistSource) {
        final isLocal = playback.queueSource == PlaybackQueueSource.offline;

        _pushDetails(
          1,
          sourceTabIndex,
          '/playback/${isLocal ? 'local' : 'server'}/playlist/${playback.queueSourcePlaylistId}',
          (_) => PlaylistDetailView(playlistId: playback.queueSourcePlaylistId!, isLocal: isLocal),
        );

        return;
      }

      await _openLibraryTrackDetails(
        track,
        isLocal: playback.isLocalPlayback || playback.queueSource == PlaybackQueueSource.offline,
        sourceTabIndex: sourceTabIndex,
      );
    } catch (_) {
      // Metadata may be unavailable if the server disconnects.
    } finally {
      _openingPlaybackDetails = false;
    }
  }

  void _showStatsDestinationUnavailable(String kind) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('This $kind is not available in the library.')));
  }

  Future<bool> _handleBackRequest() async {
    final navigator = _navigatorKeys[_selectedIndex].currentState;

    if (navigator != null && navigator.canPop()) {
      navigator.pop();

      return false;
    }

    return true;
  }

  void _handlePopInvoked(bool didPop, Object? _) {
    if (!didPop) {
      unawaited(_handleBackRequest());
    }
  }

  void _selectDestination(int index, List<int> visibleTabIndices) {
    _navigation?.cancelPending();

    final tabIndex = visibleTabIndices[index];

    if (tabIndex == _selectedIndex) {
      _navigatorKeys[tabIndex].currentState?.popUntil((route) => route.isFirst);

      return;
    }

    setState(() => _selectedIndex = tabIndex);
  }

  List<NavigationDestination> _destinations({required bool statsEnabled}) => [
    const NavigationDestination(icon: Icon(PhonoliteIcons.disc3), label: 'Library'),
    const NavigationDestination(icon: PlaylistIcon(), label: 'Playlists'),
    const NavigationDestination(icon: Icon(PhonoliteIcons.heart), label: 'Liked'),
    if (statsEnabled) const NavigationDestination(icon: StatsIcon(), label: 'Stats'),
    const NavigationDestination(icon: Icon(PhonoliteIcons.settings), label: 'Settings'),
  ];

  Widget _homeShell(
    AppController controller,
    PlaybackState playback, {
    required bool statsEnabled,
    required List<int> visibleTabIndices,
  }) => AdaptiveScaffold(
    destinations: _destinations(statsEnabled: statsEnabled),
    selectedIndex: visibleTabIndices.indexOf(_selectedIndex),
    onDestinationSelected: (index) => _selectDestination(index, visibleTabIndices),
    page: RetainedTabView(key: _tabViewKey, index: _selectedIndex, children: _pages),
    hidePlaybackChrome:
        _topRouteNames[_selectedIndex] == LoginPage.routeName ||
        _topRouteNames[_selectedIndex] == ResetUserPasswordPage.routeName,
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
    onToggleMute: controller.toggleMute,
    onToggleLike: () => unawaited(PlaybackControlsController.toggleLike(controller, playback)),
  );

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);
    final statsEnabled = controller.statsCollectionEnabled;

    // Keep the retained navigators stable while Stats is hidden from navigation.
    final visibleTabIndices = [0, 1, 2, if (statsEnabled) 3, 4];

    return DesktopMouseNavigation(
      onBack: () => _routeObservers[_selectedIndex].goBack(),
      onForward: () => _routeObservers[_selectedIndex].goForward(),
      child: LivePopScope<Object?>(
        canPop: () => !(_navigatorKeys[_selectedIndex].currentState?.canPop() ?? false),
        canPopChanges: _tabBackChanges,
        onPopInvokedWithResult: _handlePopInvoked,
        child: StreamBuilder<PlaybackState>(
          stream: controller.playbackStream,
          initialData: controller.playbackState,
          builder: (context, snapshot) {
            final playback = snapshot.data ?? controller.playbackState;

            return assemble(
              context,
              body: PageBody.box(
                child: _homeShell(
                  controller,
                  playback,
                  statsEnabled: statsEnabled,
                  visibleTabIndices: visibleTabIndices,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabRootBackObserver extends StatefulWidget {
  final VoidCallback onChanged;
  final Widget child;

  const _TabRootBackObserver({required this.onChanged, required this.child});

  @override
  State<_TabRootBackObserver> createState() => _TabRootBackObserverState();
}

class _TabRootBackObserverState extends State<_TabRootBackObserver> {
  bool? _canPop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final canPop = ModalRoute.canPopOf(context) ?? false;

    if (_canPop == canPop) {
      return;
    }

    _canPop = canPop;

    // Local history changes rebuild the route without a NavigationNotification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onChanged();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

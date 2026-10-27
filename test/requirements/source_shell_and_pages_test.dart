import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('app shell source contracts', () {
    test('main bootstraps home root and background session restore', () {
      final source = readProjectFiles([
        'lib/main.dart',
        'lib/bootstrap/phonolite_app.dart',
        'lib/bootstrap/app_startup.dart',
      ]);

      expectContainsAll(source, const [
        'GoogleFonts.config.allowRuntimeFetching = false;',
        "'PHONOLITE_URL'",
        "'https://127.0.0.1:3000/api'",
        'await Future.wait([_controller.initialize(), DisplaySettingsController.instance.initialize()]);',
        'await _controller.restoreSession();',
        'home: const HomePage(),',
      ]);
      expect(source, isNot(contains('SplashPage(')));
      expect(source, isNot(contains('LoginPage(')));
    });

    test('home page preserves five tabs, nested navigators, and back handling', () {
      final source = readProjectModule('lib/pages/home/home_page.dart');

      expectContainsAll(source, const [
        'with WidgetsBindingObserver',
        'List.generate(',
        'GlobalKey<NavigatorState>()',
        'LivePopScope<Object?>(',
        "label: 'Library'",
        "label: 'Playlists'",
        "label: 'Liked'",
        "label: 'Stats'",
        "label: 'Settings'",
        'Widget _buildTabNavigator(',
        'TabRouteObserver',
        'observers: [_routeObservers[index]]',
        'hidePlaybackChrome:',
        '_topRouteNames[_selectedIndex] == LoginPage.routeName',
        '_openCurrentPlaybackDetails()',
      ]);
    });
  });

  group('page flow source contracts', () {
    test('login page preserves two-stage server then credential flow', () {
      final source = readProjectFiles([
        'lib/pages/auth/login_page.dart',
        'lib/application/controllers/auth/login_controller.dart',
      ]);

      expectContainsAll(source, const [
        "static const String routeName = '/login';",
        'static Route<void> route(AppController controller)',
        'settings: const RouteSettings(name: routeName)',
        'GestureDetector(',
        'FocusManager.instance.primaryFocus?.unfocus()',
        'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
        "'Connect to server'",
        "'Connect'",
        "'Sign in'",
        "'Change server'",
        "'Remember me'",
        "'Open iOS Settings'",
        'LibraryHeader(',
        'ModalActionButton(',
        'app.probeServer(baseUrl)',
        'app.loginWithPassword(',
        "String get backLabel => 'Back to settings'",
        '_feature.loadSavedCredentials()',
        '_usernameController.text = saved.username;',
        'Navigator.of(context).pop()',
      ]);
      expect(source, isNot(contains("'PHONOLITE'")));
      expect(source, isNot(contains('Continue offline')));
    });

    test('library page preserves search debounce, pagination, and drilldown', () {
      final source = readProjectFiles([
        'lib/pages/library/library_page.dart',
        'lib/application/controllers/library/library_controller.dart',
        'lib/application/controllers/library/library_navigation_controller.dart',
      ]);

      expectContainsAll(source, const [
        '_collectionViewButton(',
        '_editLibraryButton(',
        'isActive: isListView',
        'SearchHud(',
        "'No local results'",
        "'Local Library'",
        "LibrarySectionHeading(title: 'Local Library'),",
        "'Download Manager'",
        "'Server Library'",
        "'Local Library Results'",
        "'Server Library Results'",
        'searchLocalLibrary(',
        "title: 'No server artists'",
        "'No server results'",
        'StreamBuilder<AuthState>',
        '_buildOfflineLibrary(controller, assemble)',
        'controller.offlineLibrarySnapshot',
        'controller.offlineLibrarySnapshotStream',
        '_offlineArtistCollectionSliver(',
        'offlineSnapshot.artistGroups',
        'ArtistRowTile(',
        'ArtistCard(',
        'LocalArtistDetailScreen(group: group)',
        'Future<void> _removeSelectedArtistDownloads(',
        'clearArtistSelection();',
        'AppLogger.warning(',
        'Failed to remove \$label: \$error',
        'showDownloadManagerPanel(context)',
        "'No downloaded tracks'",
        '_searchDebounce.schedule(const Duration(milliseconds: 450)',
        'app.loadMoreArtists()',
        'ArtistDetailScreen(artist: artist)',
        'AlbumDetailScreen(',
        'await app.queueAlbum(album.id, startTrackId: track.id);',
      ]);
      expect(source, isNot(contains('trailing: _artistSelectionMode && groups.isNotEmpty')));
    });

    test('download manager uses the shared adaptive modal shell', () {
      final panelSource = readProjectFiles([
        'lib/ui/features/downloads/widgets/download_manager_panel.dart',
        'lib/application/controllers/downloads/download_manager_controller.dart',
      ]);
      final modalSource = readProjectModule('lib/ui/shared/design_system/modals/obsidian_adaptive_modal.dart');

      expectContainsAll(panelSource, const [
        'ObsidianAdaptiveModal.show<void>',
        'useCompactSheet: false',
        'ObsidianModalSurface(',
        'presentation == ObsidianAdaptiveModalPresentation.sheet',
        "tooltip: 'Pause all'",
        "tooltip: 'Resume paused'",
        "tooltip: 'Clear all jobs and cache'",
      ]);
      expect(panelSource, isNot(contains('showDialog<void>(')));
      expect(panelSource, isNot(contains('showModalBottomSheet<void>(')));

      expectContainsAll(modalSource, const [
        'enum ObsidianAdaptiveModalPresentation',
        'static const double compactBreakpoint = ObsidianModalScope.compactBreakpoint;',
        'static const double compactHeightFactor = 0.92;',
        'static const Size maxDialogSize = Size(680, 720);',
        'showModalBottomSheet<T>(',
        'showDialog<T>(',
        'barrierColor: Colors.black.withValues(alpha: 0.45)',
        'MediaQuery.viewInsetsOf(sheetContext).bottom',
        'ObsidianModalScope(',
        'class ObsidianModalSurface extends StatelessWidget',
        'ObsidianGlassSurface(',
        'ObsidianModalActions(',
        "label: 'Close'",
      ]);
    });

    test('detail and feature pages preserve empty states and navigation labels', () {
      final artistSource = readProjectFiles([
        'lib/pages/library/artist_detail_screen.dart',
        'lib/application/controllers/library/artist_detail_controller.dart',
      ]);
      final albumSource = readProjectFiles([
        'lib/pages/library/album_detail_screen.dart',
        'lib/application/controllers/library/album_detail_controller.dart',
      ]);
      final localArtistSource = readProjectFiles([
        'lib/pages/library/local_artist_detail_screen.dart',
        'lib/application/controllers/library/local_artist_detail_controller.dart',
      ]);
      final localAlbumSource = readProjectFiles([
        'lib/pages/library/local_album_detail_screen.dart',
        'lib/application/controllers/library/local_album_detail_controller.dart',
      ]);
      final playlistsSource = readProjectFiles([
        'lib/pages/playlists/playlists_page.dart',
        'lib/application/controllers/playlists/playlists_controller.dart',
      ]);
      final playlistDetailSource = readProjectFiles([
        'lib/pages/playlists/playlist_detail_view.dart',
        'lib/application/controllers/playlists/playlist_detail_controller.dart',
      ]);
      final likedSource = readProjectFiles([
        'lib/pages/favorites/liked_page.dart',
        'lib/application/controllers/favorites/liked_controller.dart',
      ]);
      final statsSource = readProjectFiles([
        'lib/pages/listening_stats/stats_page.dart',
        'lib/application/controllers/listening_stats/stats_controller.dart',
      ]);
      final settingsSource = readProjectModule('lib/pages/settings/settings_page.dart');
      final customShuffleSource = readProjectFiles([
        'lib/pages/playback/custom_shuffle_settings_page.dart',
        'lib/ui/features/playback/widgets/shuffle_preset_editor_modal.dart',
        'lib/ui/features/playback/widgets/custom_shuffle_filter_editor.dart',
        'lib/ui/shared/music/local_server_toggle.dart',
      ]);
      final removeDownloadModalSource = readProjectModule(
        'lib/ui/features/downloads/widgets/remove_download_modal.dart',
      );
      final logsSource = readProjectModule('lib/pages/logs/logs_page.dart');
      final messageLogSource = readProjectModule('lib/ui/features/logs/widgets/message_log.dart');
      final splashSource = readProjectModule('lib/pages/splash/splash_page.dart');

      expectContainsAll(artistSource, const [
        "backLabel: 'Back to library'",
        "'Download Artist'",
        'isCompactListWidth(context)',
        'iconOnly: compactHeaderActions',
        'tooltip: downloadSummary.label',
        'TechButtonChrome',
        '.borderless',
        'DownloadSelectionToolbar',
        'ConfirmationModal.show',
        'actionChrome:',
        'confirmRemoveDownloadedDownloads',
        'controller.downloadArtist(',
        'app.removeOfflineDownloads(',
        'scope: OfflineDeletionScope.album(',
        "title: 'Artist has no albums'",
        "'Collab albums'",
      ]);
      expect(artistSource, isNot(contains("'Remove Downloads'")));
      expect(artistSource, isNot(contains('_editAlbumSelectionButton(')));
      expect(artistSource, isNot(contains("message: 'Edit'")));
      expectContainsAll(albumSource, const [
        "backLabel: 'Back to artist'",
        "'Download Album'",
        'isCompactListWidth(context)',
        'iconOnly: compactHeaderActions',
        'tooltip: downloadSummary.label',
        'TechButtonChrome',
        '.borderless',
        'DownloadSelectionToolbar',
        'downloadAlbum(',
        'confirmRemoveDownloadedTracks',
        'scope: ActionScope.server',
        "title: 'No tracks'",
        "'Pick another album to see tracks.'",
      ]);
      expect(albumSource, isNot(contains('onTrackRemoveDownload')));
      expect(albumSource, isNot(contains('_editTrackSelectionButton(')));
      expect(albumSource, isNot(contains("message: 'Edit'")));
      expect(albumSource, isNot(contains('onTrackSelectionModeRequested:')));
      expectContainsAll(localArtistSource, const [
        'class LocalArtistDetailScreen',
        "backLabel: 'Back to library'",
        'CollectionViewToggleButton(',
        'AlbumRowTile(',
        'AlbumCard(',
        'LocalAlbumDetailScreen(album: album)',
        '_editAlbumSelectionButton(',
        'DownloadSelectionToolbar',
        'confirmRemoveDownloadedTracks',
        'app.removeDownloadedTracks(',
        'scope: OfflineDeletionScope.album(',
        "title: 'Artist has no downloaded albums'",
      ]);
      expect(localArtistSource, isNot(contains("'Remove Downloads'")));
      expectContainsAll(localAlbumSource, const [
        'class LocalAlbumDetailScreen',
        "backLabel: 'Back to artist'",
        'AlbumHero(',
        '_editTrackSelectionButton(',
        'DownloadSelectionToolbar',
        'TrackSliverList(',
        'controller.playOfflineTrack(',
        'controller.toggleLocalLike',
        'scope: ActionScope.local',
        'availableOfflineDownloadForTrack(track.id)',
        'app.removeDownloadedTracks(',
        'OfflineDeletionScope.album(id: album.id, label: label)',
        "title: 'No downloaded tracks'",
      ]);
      expect(localAlbumSource, isNot(contains('onTrackRemoveDownload')));
      expect(localAlbumSource, isNot(contains('controller.removeDownloadedTrack(track)')));
      expectContainsAll(playlistsSource, const [
        "'Local Playlists'",
        "'Server Playlists'",
        "'No local playlists'",
        "'No server playlists'",
        'CollectionViewToggleButton(',
        'AlbumRowTile(',
        'AlbumCard(',
        'buildPlaylistCoverUrl(',
        "message: 'Create playlist'",
        "message: 'Edit playlists'",
        'DownloadSelectionToolbar',
        "title: 'Create playlist'",
        'showTargetSelector: canCreateServer',
        'PlaylistEditorTarget.server',
        "title: selected.length == 1 ? 'Delete playlist' : 'Delete playlists'",
        'controller.deleteLocalPlaylist(',
        'controller.deletePlaylist(',
        'controller.playLocalPlaylistFromTop(playlist.id)',
        'controller.playPlaylistFromTop(playlist.id)',
      ]);
      expect(playlistsSource, isNot(contains(" lists',")));
      expect(playlistsSource, isNot(contains('Connect to a server to show server playlists.')));
      expectContainsAll(playlistDetailSource, const [
        "backLabel: 'Back to playlists'",
        "'No tracks yet.'",
        'this.isLocal = false',
        '_feature.loadTracksIfNeeded(AppScope.of(context))',
        'loadingSliver()',
        'tracksLoading',
        'controller.queueLocalPlaylist(',
        'scope: widget.isLocal',
        'ActionScope.local',
        'ActionScope.server',
        "title: 'Rename playlist'",
        'AlbumHero(',
        'actions: _playlistPlaybackButton(',
        'ObsidianHudIconButton(',
        "'Play playlist'",
        'initialDescription: playlist.description',
        'description: description',
        'buildPlaylistCoverUrl(',
        "message: 'Edit details'",
        "message: 'Edit tracks'",
        'DownloadSelectionToolbar',
        'app.removeDownloadedTracks(tracks, label: label)',
      ]);
      expect(playlistDetailSource, isNot(contains("'Edit Details'")));
      expect(playlistDetailSource, isNot(contains("'Stop playlist'")));
      expect(playlistDetailSource, isNot(contains('controller.stop')));
      expect(playlistDetailSource, isNot(contains("title: 'Delete playlist'")));
      expect(playlistDetailSource, isNot(contains('onTrackRemoveDownload')));
      expectContainsAll(likedSource, const ['scope: ActionScope.local', 'scope: ActionScope.server']);
      expect(playlistDetailSource, isNot(contains('controller.removeDownloadedTrack(track)')));
      expectContainsAll(likedSource, const [
        'title: authState.isAuthorized',
        "'Server Liked Tracks'",
        "'No liked tracks'",
        "'No local liked tracks'",
        "'No server liked tracks'",
        'if (sectionTitle != null)',
        'controller.playLocalLikedTrack(track.id)',
        'controller.toggleLocalLike',
        'controller.playLikedTrack(track.id)',
        "message: 'Edit tracks'",
        'DownloadSelectionToolbar',
        'app.removeDownloadedTracks(tracks, label: label)',
      ]);
      expect(likedSource, isNot(contains('onRemoveDownload')));
      expect(likedSource, isNot(contains('controller.removeDownloadedTrack(track)')));
      expectContainsAll(statsSource, const [
        'controller.statsCollectionEnabledStream',
        'StatsCardsContent(',
        'navbar: StatsHeader(',
        'StatsHistoryStatus(',
        'controller.statsLastSyncedAt',
        'controller.statsSyncing',
        'app.importLocalListeningHistory()',
      ]);
      expect(statsSource, isNot(contains('Stats need a server connection.')));
      expectContainsAll(settingsSource, const [
        "title: 'SETTINGS'",
        "title: 'Custom Shuffle'",
        "sectionTitle => 'General'",
        'ListeningStatisticsSetting(',
        'controller.setStatsCollectionEnabled',
        "'Local Storage'",
        "'Metadata database'",
        "'Downloaded audio'",
        'if (!hideStoragePaths)',
        "'Logs storage'",
        'logger.updateStorageDirectory',
        "'Reset local data'",
        "'Full reset'",
        '.updateOfflineMetadataDirectory',
        '.updateOfflineDownloadsDirectory',
        '.resetOfflineData',
        "title: 'Logs'",
        "title: 'Server'",
        "'Connect / Log in'",
        "'Change server'",
        "'Disconnect'",
        "'Your server provides access to your music library.'",
        'controller.retryServerConnection()',
        "authState.isReconnecting ? 'Reconnecting...' : 'Retry'",
        'const ReloadIcon()',
        'ObsidianOverflowActionButton',
        "SettingsIconAction",
        'isCompactListWidth(context)',
        'LoginPage.route(controller)',
        'CustomShuffleSettingsPage.route()',
        'LogsPage.route()',
      ]);
      expectContainsAll(customShuffleSource, const [
        "static const String routeName = '/settings/custom-shuffle';",
        'static Route<void> route()',
        'settings: const RouteSettings(name: routeName)',
        'Scaffold(',
        "backLabel: 'Back to settings'",
        "title: 'CUSTOM SHUFFLE'",
        'ShufflePresetEditorModal(',
        'CustomShuffleFilterEditor(',
        'LocalServerToggle(',
        "label: 'SERVER'",
        "label: 'LOCAL'",
        "label: 'Select all'",
        "label: 'Clear'",
      ]);
      expectContainsAll(removeDownloadModalSource, const [
        "title: 'Remove download'",
        "confirmLabel: 'Remove'",
        'confirmVariant: TechButtonVariant.danger',
        'actionChrome: TechButtonChrome.borderless',
      ]);
      expectContainsAll(logsSource, const [
        "static const String routeName = '/settings/logs';",
        'static Route<void> route()',
        'settings: const RouteSettings(name: routeName)',
        'Scaffold(',
        "backLabel: 'Back to settings'",
        "title: 'Logs'",
      ]);
      expectContainsAll(messageLogSource, const [
        'ListView.separated(',
        'itemCount: widget.messages.length',
        'final combined = widget.messages.reversed',
      ]);
      expectContainsAll(splashSource, const ["'Connecting to saved server...'", "'Try a different server'"]);
    });
  });
}

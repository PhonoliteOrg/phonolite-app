import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('app shell source contracts', () {
    test('main bootstraps home root and background session restore', () {
      final source = readProjectFile('lib/main.dart');

      expectContainsAll(source, const [
        'GoogleFonts.config.allowRuntimeFetching = false;',
        "'PHONOLITE_URL'",
        "'http://127.0.0.1:3000/api/v1'",
        'unawaited(_controller.restoreSession());',
        'home: const HomePage(),',
      ]);
      expect(source, isNot(contains('SplashPage(')));
      expect(source, isNot(contains('LoginPage(')));
    });

    test(
      'home page preserves five tabs, nested navigators, and back handling',
      () {
        final source = readProjectFile('lib/pages/home_page.dart');

        expectContainsAll(source, const [
          'with WidgetsBindingObserver',
          'List.generate(',
          'GlobalKey<NavigatorState>()',
          'WillPopScope(',
          "label: 'Library'",
          "label: 'Playlists'",
          "label: 'Liked'",
          "label: 'Stats'",
          "label: 'Settings'",
          'Widget _buildTabNavigator(int index, Widget child)',
          '_TabRouteObserver',
          'observers: [_routeObservers[index]]',
          'hidePlaybackChrome:',
          '_topRouteNames[_selectedIndex] == LoginPage.routeName',
          '_openCurrentAlbum()',
        ]);
      },
    );
  });

  group('page flow source contracts', () {
    test('login page preserves two-stage server then credential flow', () {
      final source = readProjectFile('lib/pages/login_page.dart');

      expectContainsAll(source, const [
        "static const routeName = '/login';",
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
        "label: 'HTTP'",
        "label: 'HTTPS'",
        'widget.controller.probeServer(baseUrl)',
        'widget.controller.loginWithPassword(',
        "label: 'Back to settings'",
        '_initializeServerAddress(saved.baseUrl)',
        'Navigator.of(context).pop()',
      ]);
      expect(source, isNot(contains("'PHONOLITE'")));
      expect(source, isNot(contains('Continue offline')));
    });

    test(
      'library page preserves search debounce, pagination, and drilldown',
      () {
        final source = readProjectFile('lib/pages/library_page.dart');

        expectContainsAll(source, const [
          '_collectionViewButton(',
          '_editLibraryButton(',
          'isActive: isListView',
          'SearchHud(',
          "'No Results'",
          "'Local Library'",
          "_sectionHeaderSliver('Local Library'),",
          "'Download Manager'",
          "'Server Library'",
          "'Connected Server Results'",
          "title: 'No server artists'",
          "'No connected server results'",
          'StreamBuilder<AuthState>',
          '_buildOfflineLibrary(controller)',
          'controller.offlineLibrarySnapshot',
          'controller.offlineLibrarySnapshotStream',
          '_offlineArtistCollectionSliver(',
          'offlineSnapshot.artistGroups',
          'ArtistRowTile(',
          'ArtistCard(',
          'LocalArtistDetailScreen(group: group)',
          'Future<void> _removeSelectedArtistDownloads(',
          '_clearArtistSelection();',
          ').showSnackBar(SnackBar(content: Text(',
          'Failed to remove \$label: \$err',
          'showDownloadManagerPanel(context)',
          "'No downloaded tracks'",
          "'No offline results'",
          'Timer(const Duration(milliseconds: 450)',
          'controller.loadMoreArtists()',
          'ArtistDetailScreen(artist: artist)',
          'AlbumDetailScreen(',
          'await controller.queueAlbum(album.id, startTrackId: track.id);',
        ]);
        expect(
          source,
          isNot(
            contains('trailing: _artistSelectionMode && groups.isNotEmpty'),
          ),
        );
      },
    );

    test('download manager uses the shared adaptive modal shell', () {
      final panelSource = readProjectFile(
        'lib/widgets/modals/download_manager_panel.dart',
      );
      final modalSource = readProjectFile(
        'lib/widgets/modals/obsidian_adaptive_modal.dart',
      );

      expectContainsAll(panelSource, const [
        'ObsidianAdaptiveModal.show<void>',
        'ObsidianModalSurface(',
        'presentation == ObsidianAdaptiveModalPresentation.sheet',
        "tooltip: 'Pause all'",
        "tooltip: 'Resume paused'",
        "tooltip: 'Clear partial / failed'",
      ]);
      expect(panelSource, isNot(contains('showDialog<void>(')));
      expect(panelSource, isNot(contains('showModalBottomSheet<void>(')));

      expectContainsAll(modalSource, const [
        'enum ObsidianAdaptiveModalPresentation',
        'static const compactBreakpoint = 820.0;',
        'static const compactHeightFactor = 0.92;',
        'static const maxDialogSize = Size(680, 720);',
        'showModalBottomSheet<T>(',
        'showDialog<T>(',
        'barrierColor: Colors.black.withValues(alpha: 0.45)',
        'height: size.height * compactHeightFactor',
        'class ObsidianModalSurface extends StatelessWidget',
        'GlassPanel(',
        "tooltip: 'Close'",
      ]);
    });

    test('detail and feature pages preserve empty states and navigation labels', () {
      final artistSource = readProjectFile(
        'lib/pages/artist_detail_screen.dart',
      );
      final albumSource = readProjectFile('lib/pages/album_detail_screen.dart');
      final localArtistSource = readProjectFile(
        'lib/pages/local_artist_detail_screen.dart',
      );
      final localAlbumSource = readProjectFile(
        'lib/pages/local_album_detail_screen.dart',
      );
      final playlistsSource = readProjectFile('lib/pages/playlists_page.dart');
      final playlistDetailSource = readProjectFile(
        'lib/pages/playlist_detail_view.dart',
      );
      final likedSource = readProjectFile('lib/pages/liked_page.dart');
      final statsSource = readProjectFile('lib/pages/stats_page.dart');
      final settingsSource = readProjectFile('lib/pages/settings_page.dart');
      final customShuffleSource = readProjectFile(
        'lib/pages/custom_shuffle_settings_page.dart',
      );
      final removeDownloadModalSource = readProjectFile(
        'lib/widgets/modals/remove_download_modal.dart',
      );
      final logsSource = readProjectFile('lib/pages/logs_page.dart');
      final messageLogSource = readProjectFile(
        'lib/widgets/display/message_log.dart',
      );
      final splashSource = readProjectFile('lib/pages/splash_page.dart');

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
        'controller.removeOfflineDownloads(',
        'scope: OfflineDeletionScope.album(',
        "title: 'No albums'",
        "message: 'This artist has no albums yet.'",
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
        'controller.removeDownloadedTracks(',
        'scope: OfflineDeletionScope.album(',
        "title: 'No downloaded albums'",
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
        'controller.removeDownloadedTracks(',
        'OfflineDeletionScope.album(id: album.id, label: label)',
        "title: 'No downloaded tracks'",
      ]);
      expect(localAlbumSource, isNot(contains('onTrackRemoveDownload')));
      expect(
        localAlbumSource,
        isNot(contains('controller.removeDownloadedTrack(track)')),
      );
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
        "message: 'Play playlist'",
        'controller.playLocalPlaylistFromTop(playlist.id)',
        'controller.playPlaylistFromTop(playlist.id)',
      ]);
      expect(playlistsSource, isNot(contains('PlaylistModuleCard(')));
      expect(playlistsSource, isNot(contains(" lists',")));
      expect(
        playlistsSource,
        isNot(contains('Connect to a server to show server playlists.')),
      );
      expectContainsAll(playlistDetailSource, const [
        "backLabel: 'Back to playlists'",
        "'No tracks yet.'",
        'this.isLocal = false',
        '_loadTracksIfNeeded(AppScope.of(context))',
        'loadingSliver()',
        '_tracksLoading',
        'controller.queueLocalPlaylist(',
        'scope: widget.isLocal',
        'ActionScope.local',
        'ActionScope.server',
        "title: 'Rename playlist'",
        'AlbumHero(',
        'initialDescription: playlist.description',
        'description: description',
        'buildPlaylistCoverUrl(',
        "message: 'Edit details'",
        "message: 'Edit tracks'",
        'DownloadSelectionToolbar',
        'controller.removeDownloadedTracks(tracks, label: label)',
      ]);
      expect(playlistDetailSource, isNot(contains("'Edit Details'")));
      expect(playlistDetailSource, isNot(contains("title: 'Delete playlist'")));
      expect(playlistDetailSource, isNot(contains('onTrackRemoveDownload')));
      expectContainsAll(likedSource, const [
        'scope: ActionScope.local',
        'scope: ActionScope.server',
      ]);
      expect(
        playlistDetailSource,
        isNot(contains('controller.removeDownloadedTrack(track)')),
      );
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
        "message: 'Edit'",
        'DownloadSelectionToolbar',
        'controller.removeDownloadedTracks(tracks, label: label)',
      ]);
      expect(likedSource, isNot(contains('onRemoveDownload')));
      expect(
        likedSource,
        isNot(contains('controller.removeDownloadedTrack(track)')),
      );
      expectContainsAll(statsSource, const [
        "title: 'No stats'",
        "message: 'Listening stats will appear once enabled on the server.'",
        "'Stats need a server connection.'",
        "label: 'Connect / Log in'",
      ]);
      expectContainsAll(settingsSource, const [
        "title: 'SETTINGS'",
        "title: 'Custom Shuffle'",
        "'Offline Storage'",
        "'Metadata database'",
        "'Downloaded audio'",
        "'Managed automatically on this device - \$path'",
        "'Folder selection and custom paths are not supported on iPhone or iPad.'",
        "'Reset offline data'",
        "'Full reset'",
        '.updateOfflineMetadataDirectory',
        '.updateOfflineDownloadsDirectory',
        '.resetOfflineData',
        "title: 'Logs'",
        "'Session'",
        "'Connect / Log in'",
        "'Change server'",
        "'Disconnect'",
        "state.isReconnecting ? 'Reconnecting...' : 'Server unavailable'",
        'controller.retryServerConnection()',
        "authState.isReconnecting ? 'Reconnecting...' : 'Retry'",
        'Icons.sync_rounded',
        'ObsidianOverflowActionButton',
        '_SettingsIconAction',
        'isCompactListWidth(context)',
        'LoginPage.route(controller)',
        'CustomShuffleSettingsPage.route()',
        'LogsPage.route()',
      ]);
      expectContainsAll(customShuffleSource, const [
        "static const routeName = '/settings/custom-shuffle';",
        'static Route<void> route()',
        'settings: const RouteSettings(name: routeName)',
        'Scaffold(',
        'backgroundColor: bgDark',
        "label: 'Back to settings'",
        "title: 'Custom Shuffle'",
        "label: 'Server'",
        "label: 'Local'",
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
        "static const routeName = '/settings/logs';",
        'static Route<void> route()',
        'settings: const RouteSettings(name: routeName)',
        'Scaffold(',
        'backgroundColor: bgDark',
        "label: 'Back to settings'",
        "title: 'Logs'",
      ]);
      expectContainsAll(messageLogSource, const [
        'final displayMessages = widget.messages.reversed.toList(growable: false);',
        'final combined = displayMessages.map((entry) => entry.format()).join',
        'for (var i = 0; i < displayMessages.length; i++)',
      ]);
      expectContainsAll(splashSource, const [
        "'Connecting to saved server...'",
        "'Try a different server'",
      ]);
    });
  });
}

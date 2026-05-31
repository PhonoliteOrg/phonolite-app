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
          '_openCurrentAlbum()',
        ]);
      },
    );
  });

  group('page flow source contracts', () {
    test('login page preserves two-stage server then credential flow', () {
      final source = readProjectFile('lib/pages/login_page.dart');

      expectContainsAll(source, const [
        "'CONNECT TO SERVER'",
        "'LOG IN'",
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
        "const Text('Continue offline')",
        '_initializeServerAddress(saved.baseUrl)',
        'Navigator.of(context).pop()',
      ]);
    });

    test(
      'library page preserves search debounce, pagination, and drilldown',
      () {
        final source = readProjectFile('lib/pages/library_page.dart');

        expectContainsAll(source, const [
          'CollectionViewToggleButton(',
          'SearchHud(',
          "'No Results'",
          "'Downloaded Music'",
          "'Download Manager'",
          "'Connected Server Artists'",
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
      },
    );

    test(
      'detail and feature pages preserve empty states and navigation labels',
      () {
        final artistSource = readProjectFile(
          'lib/pages/artist_detail_screen.dart',
        );
        final albumSource = readProjectFile(
          'lib/pages/album_detail_screen.dart',
        );
        final localArtistSource = readProjectFile(
          'lib/pages/local_artist_detail_screen.dart',
        );
        final localAlbumSource = readProjectFile(
          'lib/pages/local_album_detail_screen.dart',
        );
        final playlistsSource = readProjectFile(
          'lib/pages/playlists_page.dart',
        );
        final playlistDetailSource = readProjectFile(
          'lib/pages/playlist_detail_view.dart',
        );
        final likedSource = readProjectFile('lib/pages/liked_page.dart');
        final statsSource = readProjectFile('lib/pages/stats_page.dart');
        final settingsSource = readProjectFile('lib/pages/settings_page.dart');
        final customShuffleSource = readProjectFile(
          'lib/pages/custom_shuffle_settings_page.dart',
        );
        final logsSource = readProjectFile('lib/pages/logs_page.dart');
        final splashSource = readProjectFile('lib/pages/splash_page.dart');

        expectContainsAll(artistSource, const [
          "label: 'Back to library'",
          "'Download Artist'",
          "label: 'Edit'",
          'DownloadSelectionToolbar',
          'ConfirmationModal.show',
          'confirmRemoveDownloadedDownloads',
          'controller.downloadArtist(',
          'controller.removeOfflineDownloads(',
          'scope: OfflineDeletionScope.album(',
          "title: 'No albums'",
          "message: 'This artist has no albums yet.'",
        ]);
        expect(artistSource, isNot(contains("'Remove Downloads'")));
        expectContainsAll(albumSource, const [
          "label: 'Back to artist'",
          "'Download Album'",
          "label: 'Edit'",
          'DownloadSelectionToolbar',
          'controller.downloadAlbum(',
          'confirmRemoveDownloadedTracks',
          "title: 'No tracks'",
          "'Pick another album to see tracks.'",
        ]);
        expect(albumSource, isNot(contains('onTrackRemoveDownload')));
        expectContainsAll(localArtistSource, const [
          'class LocalArtistDetailScreen',
          "label: 'Back to library'",
          'CollectionViewToggleButton(',
          'AlbumRowTile(',
          'AlbumCard(',
          'LocalAlbumDetailScreen(album: album)',
          "label: 'Edit'",
          'DownloadSelectionToolbar',
          'confirmRemoveDownloadedTracks',
          'controller.removeDownloadedTracks(',
          'scope: OfflineDeletionScope.album(',
          "title: 'No downloaded albums'",
        ]);
        expect(localArtistSource, isNot(contains("'Remove Downloads'")));
        expectContainsAll(localAlbumSource, const [
          'class LocalAlbumDetailScreen',
          "label: 'Back to artist'",
          'AlbumHero(',
          "label: 'Edit'",
          'DownloadSelectionToolbar',
          'TrackSliverList(',
          'controller.playOfflineTrack(',
          'controller.toggleLocalLike',
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
          "label: 'Create New'",
          "title: 'Create local playlist'",
          "title: 'Create server playlist'",
          "'Connect to a server to show server playlists.'",
          'controller.queueLocalPlaylist(playlist.id)',
        ]);
        expectContainsAll(playlistDetailSource, const [
          "label: 'Back to playlists'",
          "'No tracks yet.'",
          'this.isLocal = false',
          'controller.queueLocalPlaylist(',
          "title: 'Rename playlist'",
          "title: 'Delete playlist'",
          "label: 'Edit'",
          'DownloadSelectionToolbar',
          'controller.removeDownloadedTracks(tracks, label: label)',
        ]);
        expect(playlistDetailSource, isNot(contains('onTrackRemoveDownload')));
        expect(
          playlistDetailSource,
          isNot(contains('controller.removeDownloadedTrack(track)')),
        );
        expectContainsAll(likedSource, const [
          "'Local Liked Downloads'",
          "'Connected Server Liked Songs'",
          "'No local liked downloads'",
          "'No server liked tracks'",
          'controller.playLocalLikedTrack(track.id)',
          'controller.toggleLocalLike',
          'controller.playLikedTrack(track.id)',
          "label: 'Edit'",
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
          "title: 'Settings'",
          "title: 'Custom Shuffle'",
          "'Offline Storage'",
          "'Metadata database'",
          "'Downloaded audio'",
          "'Reset offline data'",
          "'Full reset'",
          '.updateOfflineMetadataDirectory',
          '.updateOfflineDownloadsDirectory',
          '.resetOfflineData',
          "title: 'Logs'",
          "title: 'Log out'",
          "'Session'",
          "'Connect / Log in'",
          "'Change server'",
          "'Disconnect'",
          'LoginPage(controller: controller)',
        ]);
        expectContainsAll(customShuffleSource, const [
          "label: 'Back to settings'",
          "title: 'Custom Shuffle'",
          "label: 'Select all'",
          "label: 'Clear'",
        ]);
        expectContainsAll(logsSource, const [
          "label: 'Back to settings'",
          "title: 'Logs'",
        ]);
        expectContainsAll(splashSource, const [
          "'Connecting to saved server...'",
          "'Try a different server'",
        ]);
      },
    );
  });
}

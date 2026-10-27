import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/favorites/liked_page.dart';
import 'package:phonolite_app/pages/library/library_page.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final entry in [
    (
      name: 'Library',
      page: (DisplaySettingsController display) => LibraryPage(displaySettings: display),
      local: 'Local Library',
      server: 'Server Library',
      change: (DisplaySettingsController display, bool value) => display.setLibraryLocalFirst(value),
    ),
    (
      name: 'Playlists',
      page: (DisplaySettingsController display) => PlaylistsPage(displaySettings: display),
      local: 'Local Playlists',
      server: 'Server Playlists',
      change: (DisplaySettingsController display, bool value) => display.setPlaylistsLocalFirst(value),
    ),
    (
      name: 'Likes',
      page: (DisplaySettingsController display) => LikedPage(displaySettings: display),
      local: 'Local Liked Tracks',
      server: 'Server Liked Tracks',
      change: (DisplaySettingsController display, bool value) => display.setLikesLocalFirst(value),
    ),
  ]) {
    testWidgets('${entry.name} updates source order and retains it across disconnection', (tester) async {
      final app = _Controller();
      final display = DisplaySettingsController(storage: _MemoryStorage());
      await display.initialize();
      await _pumpPage(tester, app, entry.page(display));

      _expectBefore(tester, entry.local, entry.server);

      await entry.change(display, false);
      await tester.pumpAndSettle();
      _expectBefore(tester, entry.server, entry.local);

      app.setConnected(false);
      await tester.pumpAndSettle();
      expect(find.text(entry.server), findsNothing);

      app.setConnected(true);
      await tester.pumpAndSettle();
      _expectBefore(tester, entry.server, entry.local);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      display.dispose();
      await app.close();
    });
  }

  testWidgets('Library search follows the same source order as browsing', (tester) async {
    final app = _Controller();
    final display = DisplaySettingsController(storage: _MemoryStorage());
    await display.initialize();
    await display.setLibraryLocalFirst(false);
    await _pumpPage(tester, app, LibraryPage(displaySettings: display));
    await tester.enterText(find.byType(TextField), 'something');
    await tester.pump(const Duration(milliseconds: 500));

    _expectBefore(tester, 'Server Library Results', 'Local Library Results');

    await display.setLibraryLocalFirst(true);
    await tester.pumpAndSettle();
    _expectBefore(tester, 'Local Library Results', 'Server Library Results');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    display.dispose();
    await app.close();
  });

  testWidgets('Server-first legacy library pages before reaching the end of local music', (tester) async {
    final app = _Controller(legacyPaging: true);
    final display = DisplaySettingsController(storage: _MemoryStorage());
    await display.initialize();
    await display.setLibraryLocalFirst(false);
    await _pumpPage(tester, app, LibraryPage(displaySettings: display));

    expect(app.artistPageRequests, 1);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.extentAfter, greaterThan(720));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    display.dispose();
    await app.close();
  });
}

Future<void> _pumpPage(WidgetTester tester, _Controller app, Widget page) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(AppScope(controller: app, child: wrapInTestApp(page)));
  await tester.pumpAndSettle();
}

void _expectBefore(WidgetTester tester, String first, String second) {
  expect(find.text(first), findsOneWidget);
  expect(find.text(second), findsOneWidget);
  expect(tester.getTopLeft(find.text(first)).dy, lessThan(tester.getTopLeft(find.text(second)).dy));
}

class _MemoryStorage extends DisplaySettingsStorage {
  @override
  Future<DisplaySettings> read() async => const DisplaySettings();

  @override
  Future<void> write(DisplaySettings settings) async {}
}

class _Controller extends AppController {
  static final _artist = Artist(id: 'server-artist', name: 'Server Artist', albumCount: 1);

  final bool legacyPaging;
  final _authChanges = StreamController<AuthState>.broadcast();
  bool _connected = true;
  int artistPageRequests = 0;

  _Controller({this.legacyPaging = false}) : super(connection: ServerConnection(baseUrl: 'http://server.test/api'));

  @override
  AuthState get authState => AuthState(isAuthorized: _connected, baseUrl: connection.baseUrl);

  @override
  Stream<AuthState> get authStream => _authChanges.stream;

  @override
  List<Artist> get artists => legacyPaging ? [_artist] : const [];

  @override
  bool get hasMoreArtists => legacyPaging && artistPageRequests == 0;

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot {
    final tracks = <Track>[
      if (legacyPaging)
        for (var index = 0; index < 30; index++)
          offlineTestTrack(id: 'local-$index', artist: 'Local $index', artistId: 'local-artist-$index'),
    ];

    return OfflineLibrarySnapshot(
      tracks: tracks,
      artistGroups: offlineArtistGroups(tracks),
      liked: const [],
      playlists: const [],
      playlistTracks: const [],
      revision: 1,
    );
  }

  @override
  Future<void> close() async {
    await _authChanges.close();
    await super.close();
  }

  void setConnected(bool value) {
    _connected = value;
    _authChanges.add(authState);
  }

  @override
  Future<void> loadArtists({bool refresh = false}) async {}

  @override
  Future<void> loadMoreArtists() async {
    artistPageRequests++;
  }

  @override
  Future<Artist> fetchArtistMetadata(String id, {bool refresh = false}) async => _artist;

  @override
  Future<void> loadLocalPlaylists() async {}

  @override
  Future<void> loadPlaylists() async {}

  @override
  Future<void> loadLocalLikedTracks() async {}

  @override
  Future<void> loadLikedTracks() async {}

  @override
  Future<void> search(String query, {String? filter}) async {}
}

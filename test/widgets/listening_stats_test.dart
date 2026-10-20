import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/app_log.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/settings_page.dart';
import 'package:phonolite_app/pages/stats_page.dart';
import 'package:phonolite_app/widgets/display/artist_row_tile.dart';
import 'package:phonolite_app/widgets/display/stats_cards.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/modals/obsidian_dialog.dart';
import 'package:phonolite_app/widgets/ui/obsidian_glass_surface.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

import '../support/auth_test_helpers.dart';
import '../support/widget_test_helpers.dart';

class _StatsController extends Fake implements AppController {
  _StatsController() {
    server.setTrust(testServerTrust);
  }

  final collectionUpdates = StreamController<bool>.broadcast();
  final statsUpdates = StreamController<StatsResponse?>.broadcast();
  final authUpdates = StreamController<AuthState>.broadcast();
  final artistUpdates = StreamController<List<Artist>>.broadcast();
  final offlineUpdates = StreamController<OfflineLibrarySnapshot>.broadcast();
  bool enabled = true;
  bool serverEnabled = true;
  bool importAvailable = false;
  String? syncMessage;
  int pending = 0;
  int loads = 0;
  int imports = 0;
  int localResets = 0;
  int accountResets = 0;
  bool failReset = false;
  final choices = <bool>[];
  AuthState auth = AuthState(baseUrl: '', status: SessionStatus.offline);
  StatsResponse value = _history();
  final server = ServerConnection(baseUrl: 'https://music.example/api/v1');
  List<Artist> artistMetadata = [
    Artist(id: 'artist', name: 'A very long artist name', albumCount: 0),
  ];
  OfflineLibrarySnapshot library = const OfflineLibrarySnapshot(
    tracks: [],
    artistGroups: [],
    liked: [],
    playlists: [],
    playlistTracks: [],
    revision: 0,
  );

  @override
  ServerConnection get connection => server;
  @override
  List<Artist> get artists => artistMetadata;
  @override
  Stream<List<Artist>> get artistsStream => artistUpdates.stream;
  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => library;
  @override
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream =>
      offlineUpdates.stream;
  @override
  Map<String, String> get artworkHeaders => server.authorizationHeaders;

  @override
  bool get statsCollectionEnabled => enabled;
  @override
  Stream<bool> get statsCollectionEnabledStream => collectionUpdates.stream;
  @override
  StatsResponse get stats => value;
  @override
  Stream<StatsResponse?> get statsStream => statsUpdates.stream;
  @override
  AuthState get authState => auth;
  @override
  Stream<AuthState> get authStream => authUpdates.stream;
  @override
  bool get statsSyncing => false;
  @override
  int get pendingStatsCount => pending;
  @override
  DateTime? get statsLastSyncedAt => null;
  @override
  String? get statsSyncMessage => syncMessage;
  @override
  bool get statsServerCollectionEnabled => serverEnabled;
  @override
  bool get canImportLocalStats => importAvailable;
  @override
  List<LogEntry> get messages => [];
  @override
  Stream<List<LogEntry>> get messageStream => const Stream.empty();
  @override
  CustomShuffleSettings get customShuffleSettings =>
      const CustomShuffleSettings();
  @override
  Stream<CustomShuffleSettings> get customShuffleSettingsStream =>
      const Stream.empty();
  @override
  OfflineStorageLocations? get offlineStorageLocations => null;
  @override
  Stream<OfflineStorageLocations> get offlineStorageLocationsStream =>
      const Stream.empty();

  @override
  Future<void> setStatsCollectionEnabled(bool next) async {
    choices.add(next);
    enabled = next;
    collectionUpdates.add(next);
    statsUpdates.add(value);
  }

  @override
  Future<void> loadStats({int? year, int? month}) async {
    loads++;
    value = _history(year: year ?? value.year, month: month);
    statsUpdates.add(value);
  }

  @override
  Future<void> importLocalListeningHistory() async {
    imports++;
    importAvailable = false;
    statsUpdates.add(value);
  }

  @override
  Future<void> resetLocalListeningHistory() async {
    localResets++;
    if (failReset) throw StateError('Storage unavailable');
  }

  @override
  Future<void> resetAccountListeningHistory() async {
    accountResets++;
    if (failReset) throw ApiException(503, 'Unavailable');
  }

  @override
  Future<void> resetListeningStatistics() async {
    if (auth.isAuthorized) {
      accountResets++;
      if (failReset) throw ApiException(503, 'Unavailable');
    } else if (failReset) {
      throw StateError('Storage unavailable');
    }
    localResets++;
  }

  @override
  Future<void> close() async {
    await collectionUpdates.close();
    await statsUpdates.close();
    await authUpdates.close();
    await artistUpdates.close();
    await offlineUpdates.close();
  }
}

StatsResponse _history({int year = 2026, int? month}) => StatsResponse(
  year: year,
  month: month,
  totalMinutes: 42,
  totalListeningMs: 42 * 60000,
  totalPlays: 8,
  uniqueTracks: 1,
  uniqueArtists: 1,
  topArtists: [
    StatsItem(id: 'artist', name: 'A very long artist name', minutes: 42),
  ],
  topTracks: [
    StatsTrack(
      id: 'track',
      title: 'An offline track',
      artist: 'A very long artist name',
      minutes: 42,
      plays: 8,
    ),
  ],
  topGenres: [StatsItem(id: 'ambient', name: 'Ambient', minutes: 42)],
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _disposeController(WidgetTester tester, _StatsController controller) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final closing = controller.close();
    await tester.pump();
    await closing;
  });
}

Widget _app(_StatsController controller, Widget child, {double scale = 1}) =>
    MaterialApp(
      theme: ObsidianTheme.build(scale: scale),
      home: Scaffold(
        body: ObsidianScale(
          scale: scale,
          child: AppScope(controller: controller, child: child),
        ),
      ),
    );

Future<void> _openHistoryStatus(WidgetTester tester) async {
  final status = find.byTooltip('Listening history status');
  await tester.ensureVisible(status);
  await tester.pumpAndSettle();
  await tester.tap(status);
  await tester.pumpAndSettle();
  expect(find.byType(ObsidianAlertDialog), findsOneWidget);
  expect(find.text('Listening history'), findsOneWidget);
  expect(find.text('CLOSE'), findsOneWidget);
  expect(find.byType(PopupMenuItem<String>), findsNothing);
}

Future<void> _dismissHistoryStatus(WidgetTester tester) async {
  await tester.tap(find.text('CLOSE'));
  await tester.pumpAndSettle();
  expect(find.byType(ObsidianAlertDialog), findsNothing);
}

void main() {
  setUp(configureTestFonts);

  for (final status in SessionStatus.values) {
    testWidgets(
      'one statistics reset is available for connection state $status',
      (tester) async {
        _viewport(tester, const Size(320, 812));
        final controller = _StatsController()
          ..auth = AuthState(baseUrl: 'saved-server', status: status);
        _disposeController(tester, controller);
        await tester.pumpWidget(
          _app(controller, const SettingsPage(), scale: 0.7),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reset-listening-statistics')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('reset-device-only-history')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('reset-account-history')),
          findsNothing,
        );
        expect(find.text('Reset listening statistics'), findsOneWidget);
        expect(controller.localResets, 0);
        expect(controller.accountResets, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final account in [false, true]) {
    testWidgets(
      '${account ? 'account' : 'local'} reset requires confirmation and preserves collection toggle',
      (tester) async {
        _viewport(tester, const Size(375, 812));
        final controller = _StatsController()
          ..enabled = true
          ..auth = AuthState(
            baseUrl: 'saved-server',
            status: account
                ? SessionStatus.authenticated
                : SessionStatus.offline,
          );
        _disposeController(tester, controller);
        await tester.pumpWidget(
          _app(controller, const SettingsPage(), scale: 0.7),
        );
        await tester.pumpAndSettle();
        Future<void> openReset() async {
          final reset = find.byKey(
            const ValueKey('reset-listening-statistics'),
          );
          await tester.ensureVisible(reset);
          await tester.pumpAndSettle();
          await tester.tap(reset);
          await tester.pumpAndSettle();
        }

        await openReset();
        expect(find.text('Reset listening statistics?'), findsOneWidget);
        expect(
          find.textContaining(
            account
                ? 'saved on this device and for your connected server account'
                : 'Server statistics and statistics saved on other devices are kept',
          ),
          findsOneWidget,
        );
        expect(controller.localResets, 0);
        expect(controller.accountResets, 0);
        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(controller.localResets, 0);
        expect(controller.accountResets, 0);
        await openReset();
        await tester.tap(find.text('RESET STATISTICS'));
        await tester.pumpAndSettle();
        expect(controller.localResets, 1);
        expect(controller.accountResets, account ? 1 : 0);
        expect(controller.enabled, isTrue);
        expect(controller.choices, isEmpty);
        expect(find.text('Listening statistics reset.'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(MaterialBanner), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final signedIn in [false, true]) {
    testWidgets(
      'reset controls follow collection setting, signed in $signedIn',
      (tester) async {
        final controller = _StatsController()
          ..enabled = false
          ..auth = AuthState(
            baseUrl: 'saved-server',
            status: signedIn
                ? SessionStatus.authenticated
                : SessionStatus.offline,
          );
        _disposeController(tester, controller);
        await tester.pumpWidget(_app(controller, const SettingsPage()));
        await tester.pumpAndSettle();
        final reset = find.byKey(const ValueKey('reset-listening-statistics'));
        expect(reset, findsNothing);

        final toggle = find.byKey(
          const ValueKey('listening-statistics-switch'),
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(reset, findsOneWidget);

        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(reset, findsNothing);
        expect(controller.localResets, 0);
        expect(controller.accountResets, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('turning collection off during confirmation cancels the reset', (
    tester,
  ) async {
    final controller = _StatsController();
    _disposeController(tester, controller);
    await tester.pumpWidget(_app(controller, const SettingsPage()));
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('reset-listening-statistics'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await controller.setStatsCollectionEnabled(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESET STATISTICS'));
    await tester.pumpAndSettle();
    expect(controller.localResets, 0);
    expect(reset, findsNothing);
  });

  testWidgets(
    'account change during confirmation prevents reset of a different account',
    (tester) async {
      final controller = _StatsController()
        ..auth = AuthState(
          baseUrl: 'saved-server',
          status: SessionStatus.authenticated,
        );
      _disposeController(tester, controller);
      await tester.pumpWidget(_app(controller, const SettingsPage()));
      await tester.pumpAndSettle();
      final reset = find.byKey(const ValueKey('reset-listening-statistics'));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      controller.server.setToken('different-account');
      controller.authUpdates.add(controller.auth);
      await tester.pumpAndSettle();
      await tester.tap(find.text('RESET STATISTICS'));
      await tester.pumpAndSettle();
      expect(controller.accountResets, 0);
      expect(find.text('Listening statistics reset.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed account reset logs failure without notifications and keeps controls usable',
    (tester) async {
      final failures = <LogEntry>[];
      final LogListener listener = failures.add;
      AppLogger.instance.attach(listener, includeHistory: false);
      addTearDown(() => AppLogger.instance.detach(listener));
      final controller = _StatsController()
        ..failReset = true
        ..auth = AuthState(
          baseUrl: 'saved-server',
          status: SessionStatus.authenticated,
        );
      _disposeController(tester, controller);
      await tester.pumpWidget(_app(controller, const SettingsPage()));
      await tester.pumpAndSettle();
      final reset = find.byKey(const ValueKey('reset-listening-statistics'));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.text('RESET STATISTICS'));
      await tester.pumpAndSettle();
      expect(controller.accountResets, 1);
      expect(find.text('Listening statistics reset.'), findsNothing);
      expect(
        find.textContaining('Could not reset listening statistics.'),
        findsNothing,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(
        failures.any(
          (entry) =>
              entry.level == LogLevel.warning &&
              entry.message.contains('Could not reset listening statistics.'),
        ),
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('listening-statistics-switch')),
            )
            .onChanged,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('statistics title fits beside its actions while resizing', (
    tester,
  ) async {
    final font = FontLoader(
      GoogleFonts.rajdhani(fontWeight: FontWeight.w700).fontFamily!,
    )..addFont(rootBundle.load('assets/fonts/Rajdhani-Bold.ttf'));
    await font.load();
    _viewport(tester, const Size(1280, 900));
    final controller = _StatsController();
    _disposeController(tester, controller);

    for (final width in [
      1280.0,
      800.0,
      700.0,
      640.0,
      620.0,
      600.0,
      599.0,
      560.0,
      430.0,
      375.0,
      320.0,
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _app(
          controller,
          const StatsPage(),
          scale: ObsidianScale.compute(width),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.renderObject<RenderParagraph>(
        find.text('LISTENING STATISTICS'),
      );
      expect(
        title.didExceedMaxLines,
        isFalse,
        reason: 'The complete title should remain visible at width $width.',
      );
      final titleBounds = Rect.fromPoints(
        title.localToGlobal(Offset.zero),
        title.localToGlobal(title.size.bottomRight(Offset.zero)),
      );
      final status = tester.getRect(find.byTooltip('Listening history status'));
      final refresh = tester.getRect(
        find.byTooltip('Refresh listening history'),
      );
      expect(titleBounds.left, closeTo(20, 0.01));
      expect(titleBounds.right, lessThanOrEqualTo(status.left - 9.99));
      expect(refresh.right, closeTo(width - 20, 0.01));
      expect(refresh.width, greaterThanOrEqualTo(38));
      if (width == 1280) {
        expect(titleBounds.height, closeTo(56, 0.01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('artist artwork uses authenticated server URLs and live metadata', (
    tester,
  ) async {
    final controller = _StatsController()
      ..auth = AuthState(
        baseUrl: 'https://music.example/api/v1',
        status: SessionStatus.authenticated,
      )
      ..artistMetadata = [];
    controller.server.setToken('test-artwork-token');
    _disposeController(tester, controller);
    await tester.pumpWidget(_app(controller, const StatsPage()));
    await tester.pumpAndSettle();
    var tile = tester.widget<ArtistRowTile>(find.byType(ArtistRowTile));
    expect(
      tile.coverUrl,
      'https://music.example/api/v1/library/artists/artist/cover?kind=logo',
    );
    expect(tile.headers, {'Authorization': 'Bearer test-artwork-token'});
    expect(controller.loads, 1);

    controller.artistMetadata = [
      Artist(
        id: 'artist',
        name: 'A very long artist name',
        albumCount: 1,
        logoRef: 'logo revision/2',
      ),
    ];
    controller.artistUpdates.add(controller.artistMetadata);
    await tester.pumpAndSettle();
    tile = tester.widget<ArtistRowTile>(find.byType(ArtistRowTile));
    expect(
      tile.coverUrl,
      'https://music.example/api/v1/library/artists/artist/cover?kind=logo&v=logo%20revision%2F2',
    );
    expect(controller.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline account artwork stays within the saved server catalog', (
    tester,
  ) async {
    final controller = _StatsController()
      ..auth = AuthState(
        baseUrl: 'https://music.example/api/v1',
        status: SessionStatus.serverUnavailable,
      );
    controller.server.setToken('test-artwork-token');
    _disposeController(tester, controller);
    OfflineLibrarySnapshot artworkLibrary(String origin, int revision) =>
        OfflineLibrarySnapshot(
          tracks: [
            Track(
              id: 'track',
              title: 'An offline track',
              artist: 'A very long artist name',
              artistId: 'artist',
              album: 'Offline album',
              durationMs: 180000,
              liked: false,
              inPlaylists: false,
              serverBaseUrl: origin,
              artistArtPath: 'C:/test-art/artist.png',
            ),
          ],
          artistGroups: [],
          liked: [],
          playlists: [],
          playlistTracks: [],
          revision: revision,
        );
    controller.library = artworkLibrary('https://other.example/api/v1', 1);
    await tester.pumpWidget(_app(controller, const StatsPage()));
    await tester.pumpAndSettle();
    var tile = tester.widget<ArtistRowTile>(find.byType(ArtistRowTile));
    expect(tile.coverUrl, isNull);
    expect(tile.headers, isEmpty);

    controller.library = artworkLibrary(controller.server.baseUrl, 2);
    controller.offlineUpdates.add(controller.library);
    await tester.pumpAndSettle();
    tile = tester.widget<ArtistRowTile>(find.byType(ArtistRowTile));
    expect(tile.coverUrl, 'C:/test-art/artist.png');
    expect(tile.headers, isEmpty);
    expect(controller.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'anonymous local history uses saved artwork and name-only artists',
    (tester) async {
      final controller = _StatsController()
        ..library = OfflineLibrarySnapshot(
          tracks: [
            Track(
              id: 'track',
              title: 'An offline track',
              artist: 'A very long artist name',
              artistId: 'artist',
              album: 'Offline album',
              durationMs: 180000,
              liked: false,
              inPlaylists: false,
              serverBaseUrl: 'https://other.example/api/v1',
              artistArtPath: 'C:/test-art/artist.png',
            ),
            Track(
              id: 'name-only-track',
              title: 'A local file',
              artist: 'Name Only',
              album: 'Local album',
              durationMs: 180000,
              liked: false,
              inPlaylists: false,
              artistArtPath: 'C:/test-art/name-only.png',
            ),
          ],
          artistGroups: [],
          liked: [],
          playlists: [],
          playlistTracks: [],
          revision: 1,
        );
      _disposeController(tester, controller);
      await tester.pumpWidget(_app(controller, const StatsPage()));
      await tester.pumpAndSettle();
      final tile = tester.widget<ArtistRowTile>(find.byType(ArtistRowTile));
      expect(tile.coverUrl, 'C:/test-art/artist.png');
      expect(tile.headers, isEmpty);
      final cards = tester.widget<StatsCards>(find.byType(StatsCards));
      expect(
        cards.artistCoverUrl!(
          StatsItem(id: 'Name Only', name: 'Name Only', minutes: 1),
        ),
        'C:/test-art/name-only.png',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'summary uses complete period counts and displays partial minutes',
    (tester) async {
      _viewport(tester, const Size(375, 812));
      final stats = StatsResponse(
        year: 2026,
        month: null,
        totalMinutes: 0,
        totalListeningMs: 12500,
        totalPlays: 0,
        uniqueTracks: 47,
        uniqueArtists: 11,
        topTracks: [],
        topArtists: [],
        topGenres: [],
      );
      await tester.pumpWidget(
        wrapInTestApp(
          StatsCards(
            stats: stats,
            onYearChanged: (_) {},
            onMonthChanged: (_) {},
          ),
        ),
      );
      expect(find.text('12s'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('TOTAL PLAYS'), findsOneWidget);
      expect(find.text('No listening in this period yet.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('genre bars preserve listening shorter than a minute', (
    tester,
  ) async {
    _viewport(tester, const Size(900, 812));
    final stats = StatsResponse(
      year: 2026,
      month: null,
      totalMinutes: 1,
      totalListeningMs: 60500,
      topTracks: [],
      topArtists: [],
      topGenres: [
        StatsItem(id: 'jazz', name: 'jazz', minutes: 0, listeningMs: 12500),
        StatsItem(id: 'rock', name: 'ROCK', minutes: 0, listeningMs: 47500),
        StatsItem(id: 'folk', name: 'Folk', minutes: 0, listeningMs: 500),
      ],
    );
    await tester.pumpWidget(
      wrapInTestApp(
        StatsCards(stats: stats, onYearChanged: (_) {}, onMonthChanged: (_) {}),
      ),
    );

    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Folk'), findsOneWidget);
    expect(find.text('12s'), findsOneWidget);
    expect(find.text('47s'), findsOneWidget);
    expect(find.text('<1s'), findsOneWidget);
    final bars = tester.widgetList<FractionallySizedBox>(
      find.descendant(
        of: find.byType(StatsCards),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(bars.map((bar) => bar.widthFactor), [
      closeTo(12500 / 60500, 0.000001),
      closeTo(47500 / 60500, 0.000001),
      closeTo(500 / 60500, 0.000001),
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(1200, 900),
    const Size(900, 812),
    const Size(375, 812),
  ]) {
    testWidgets('rankings fit and genres share the artist panel at $size', (
      tester,
    ) async {
      _viewport(tester, size);
      final stats = StatsResponse(
        year: 2026,
        month: null,
        totalMinutes: 120,
        topArtists: [
          for (var i = 1; i <= 8; i++)
            StatsItem(id: 'artist-$i', name: 'Artist $i', minutes: 20 - i),
        ],
        topTracks: [
          for (var i = 1; i <= 12; i++)
            StatsTrack(
              id: 'track-$i',
              title: 'Track $i',
              artist: 'Artist $i',
              minutes: 20 - i,
              plays: 20 - i,
            ),
        ],
        topGenres: [
          for (var i = 1; i <= 5; i++)
            StatsItem(id: 'genre-$i', name: 'Genre $i', minutes: 20 - i),
        ],
      );
      await tester.pumpWidget(
        wrapInTestApp(
          StatsCards(
            stats: stats,
            onYearChanged: (_) {},
            onMonthChanged: (_) {},
          ),
        ),
      );

      expect(find.byType(ArtistRowTile), findsNWidgets(5));
      expect(find.text('Artist 5'), findsOneWidget);
      expect(find.text('Artist 6'), findsNothing);
      for (var i = 1; i <= 10; i++) {
        expect(find.text('Track $i'), findsOneWidget);
      }
      expect(find.text('Track 11'), findsNothing);
      expect(find.text('Track 12'), findsNothing);

      // Sharing a backdrop is valid only while every glass panel has its own
      // rectangle, including when the analysis panels stack on narrow screens.
      final surfaces = find.byType(ObsidianGlassSurface);
      final rectangles = [
        for (var i = 0; i < surfaces.evaluate().length; i++)
          tester.getRect(surfaces.at(i)),
      ];
      for (var i = 0; i < rectangles.length; i++) {
        for (var j = i + 1; j < rectangles.length; j++) {
          expect(
            rectangles[i].overlaps(rectangles[j]),
            isFalse,
            reason: 'Stats glass panels $i and $j must not share pixels',
          );
        }
      }

      Rect panel(String title) => tester.getRect(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(ObsidianGlassSurface),
        ),
      );
      final genres = panel('TOP GENRES');
      final artists = panel('TOP ARTISTS');
      if (size.width >= 900) {
        expect(genres.top, closeTo(artists.top, 0.01));
        expect(genres.height, closeTo(artists.height, 0.01));
        final genrePositions = [
          for (var i = 1; i <= 5; i++)
            tester.getCenter(find.text('Genre $i')).dy,
        ];
        final spacing = genrePositions[1] - genrePositions[0];
        for (var i = 2; i < genrePositions.length; i++) {
          expect(
            genrePositions[i] - genrePositions[i - 1],
            closeTo(spacing, 0.01),
          );
        }
        expect(
          genrePositions.last - genrePositions.first,
          greaterThan(artists.height * 0.6),
        );
      } else {
        expect(genres.bottom, lessThan(artists.top));
      }
      await tester.ensureVisible(find.text('Track 10'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'genre chart includes the remainder and reconciles with total time',
    (tester) async {
      _viewport(tester, const Size(900, 812));
      final stats = StatsResponse.fromJson({
        'year': 2026,
        'total_minutes': 10,
        'total_listening_ms': 600001,
        'top_artists': [],
        'top_tracks': [],
        'top_genres': [
          for (var index = 0; index < 5; index++)
            {
              'id': 'genre-$index',
              'name': 'Genre $index',
              'minutes': 1,
              'listening_ms': 100000,
            },
        ],
        'other_genre_listening_ms': 50000,
        'unclassified_listening_ms': 50001,
      });
      await tester.pumpWidget(
        wrapInTestApp(
          StatsCards(
            stats: stats,
            onYearChanged: (_) {},
            onMonthChanged: (_) {},
          ),
        ),
      );
      expect(find.text('10m 0s'), findsOneWidget);
      expect(find.text('Other Genres'), findsOneWidget);
      expect(find.text('Unclassified'), findsOneWidget);
      final bars = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(StatsCards),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(bars, hasLength(7));
      expect(
        bars.fold<double>(0, (sum, bar) => sum + bar.widthFactor!),
        closeTo(1, 0.000001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline history renders and refreshes without a login gate', (
    tester,
  ) async {
    _viewport(tester, const Size(375, 812));
    final controller = _StatsController();
    _disposeController(tester, controller);
    await tester.pumpWidget(_app(controller, const StatsPage(), scale: 0.7));
    await tester.pumpAndSettle();
    await _openHistoryStatus(tester);
    expect(
      find.text('Listening is saved on this device, even offline.'),
      findsOneWidget,
    );
    await _dismissHistoryStatus(tester);
    expect(find.text('42m 0s'), findsWidgets);
    expect(find.text('Connect / Log in'), findsNothing);
    expect(controller.loads, 1);
    await tester.tap(find.byTooltip('Refresh listening history'));
    await tester.pumpAndSettle();
    expect(controller.loads, 2);
    await tester.tap(find.byIcon(PhonoliteIcons.chevronRight).last);
    await tester.pumpAndSettle();
    expect(controller.value.year, 2027);
    expect(find.text('2027'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('genre durations update from the stats stream within a minute', (
    tester,
  ) async {
    _viewport(tester, const Size(900, 812));
    final controller = _StatsController();
    _disposeController(tester, controller);
    await tester.pumpWidget(_app(controller, const StatsPage()));
    await tester.pumpAndSettle();
    final initialLoads = controller.loads;

    void checkpoint(int milliseconds) {
      controller.value = StatsResponse(
        year: 2026,
        month: null,
        totalMinutes: 10,
        totalListeningMs: 600000,
        topTracks: [],
        topArtists: [],
        topGenres: [
          StatsItem(
            id: 'acid-jazz',
            name: 'Acid Jazz',
            minutes: milliseconds ~/ 60000,
            listeningMs: milliseconds,
          ),
        ],
      );
      controller.statsUpdates.add(controller.value);
    }

    checkpoint(60000);
    await tester.pumpAndSettle();
    expect(find.text('1m 0s'), findsOneWidget);
    checkpoint(62500);
    await tester.pumpAndSettle();
    expect(find.text('1m 2s'), findsOneWidget);
    expect(find.text('1m 0s'), findsNothing);
    final bar = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(StatsCards),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(bar.widthFactor, closeTo(62500 / 600000, 0.000001));
    expect(controller.loads, initialLoads);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings starts enabled and switches collection off on this device',
    (tester) async {
      _viewport(tester, const Size(320, 812));
      final controller = _StatsController();
      _disposeController(tester, controller);
      await tester.pumpWidget(
        _app(controller, const SettingsPage(), scale: 0.7),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('listening-statistics-switch'));
      await tester.ensureVisible(toggle);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(find.text('Listening statistics'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(controller.choices, [false]);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(
        find.text(
          'New listening statistics and uploads are stopped on this device. Existing statistics are kept.',
        ),
        findsOneWidget,
      );
      expect(controller.value.totalMinutes, 42);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_app(controller, const StatsPage(), scale: 0.7));
      await tester.pumpAndSettle();
      await _openHistoryStatus(tester);
      expect(
        find.textContaining('Collection is off on this device.'),
        findsOneWidget,
      );
      expect(find.text('42m 0s'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _dismissHistoryStatus(tester);
    },
  );

  testWidgets(
    'account history fits narrow screens and reports offline sync status',
    (tester) async {
      _viewport(tester, const Size(320, 812));
      final controller = _StatsController()
        ..auth = AuthState(
          baseUrl: 'saved-server',
          status: SessionStatus.serverUnavailable,
        )
        ..pending = 12;
      _disposeController(tester, controller);
      await tester.pumpWidget(
        _app(
          controller,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: const StatsPage(),
            ),
          ),
          scale: 0.7,
        ),
      );
      await tester.pumpAndSettle();
      await _openHistoryStatus(tester);
      expect(find.text('Account history'), findsNothing);
      expect(find.textContaining('waiting to sync'), findsNothing);
      expect(
        find.textContaining('Offline. Listening is saved'),
        findsOneWidget,
      );
      await _dismissHistoryStatus(tester);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.serverEnabled = false;
      controller.statsUpdates.add(controller.value);
      await tester.pumpAndSettle();
      await _openHistoryStatus(tester);
      expect(
        find.text(
          'Server sync is disabled. Listening is saved on this device.',
        ),
        findsOneWidget,
      );
      await _dismissHistoryStatus(tester);
      controller.syncMessage =
          'Listening history could not be saved on this device.';
      controller.statsUpdates.add(controller.value);
      await tester.pumpAndSettle();
      await _openHistoryStatus(tester);
      expect(find.text(controller.syncMessage!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dismissHistoryStatus(tester);
    },
  );

  testWidgets('local history import requires an explicit confirmation', (
    tester,
  ) async {
    final controller = _StatsController()
      ..auth = AuthState(
        baseUrl: 'saved-server',
        status: SessionStatus.authenticated,
      )
      ..importAvailable = true;
    _disposeController(tester, controller);
    await tester.pumpWidget(_app(controller, const StatsPage()));
    await tester.pumpAndSettle();
    expect(controller.imports, 0);
    await _openHistoryStatus(tester);
    await tester.tap(find.text('ADD LOCAL HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('Add local listening history?'), findsOneWidget);
    expect(controller.imports, 0);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(controller.imports, 0);
    await _openHistoryStatus(tester);
    await tester.tap(find.text('ADD LOCAL HISTORY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADD HISTORY'));
    await tester.pumpAndSettle();
    expect(controller.imports, 1);
    await _openHistoryStatus(tester);
    expect(find.text('ADD LOCAL HISTORY'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dismissHistoryStatus(tester);
  });
}

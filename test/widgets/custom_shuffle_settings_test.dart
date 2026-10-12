import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';
import 'package:phonolite_app/pages/custom_shuffle_settings_page.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/ui/hover_row.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

const _serverAlpha = 'Alpha artist with a very long name for narrow screens';
const _localAlpha = 'Alpha downloaded artist with a very long name';

class _ShuffleController extends Fake implements AppController {
  _ShuffleController({
    this.value = const CustomShuffleSettings(),
    this.authorized = true,
  });

  CustomShuffleSettings value;
  final bool authorized;
  final saves = <CustomShuffleSettings>[];
  int loadAllCalls = 0;

  final _artists = [
    Artist(
      id: 'shared-artist',
      name: _serverAlpha,
      albumCount: 1,
      genres: ['Ambient'],
    ),
    Artist(
      id: 'server-artist',
      name: 'Beta artist',
      albumCount: 1,
      genres: ['Jazz'],
    ),
  ];

  final _library = OfflineLibrarySnapshot(
    tracks: const [],
    artistGroups: [
      OfflineArtistGroup(
        id: 'shared-artist',
        name: _localAlpha,
        albums: const [],
        metadata: Artist(
          id: 'shared-artist',
          name: _localAlpha,
          albumCount: 0,
          genres: ['Ambient'],
        ),
      ),
      OfflineArtistGroup(
        id: 'local-artist',
        name: 'Delta downloaded artist',
        albums: const [],
        metadata: Artist(
          id: 'local-artist',
          name: 'Delta downloaded artist',
          albumCount: 0,
          genres: ['Rock'],
        ),
      ),
    ],
    liked: const [],
    playlists: const [],
    playlistTracks: const [],
    revision: 0,
  );

  @override
  AuthState get authState =>
      AuthState(baseUrl: 'https://music.example', isAuthorized: authorized);

  @override
  CustomShuffleSettings get customShuffleSettings => value;

  @override
  List<Artist> get artists => _artists;

  @override
  Stream<List<Artist>> get artistsStream => const Stream.empty();

  @override
  bool get artistsLoading => false;

  @override
  Stream<bool> get artistsLoadingStream => const Stream.empty();

  @override
  bool get hasMoreArtists => false;

  @override
  OfflineLibrarySnapshot get offlineLibrarySnapshot => _library;

  @override
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream =>
      const Stream.empty();

  @override
  Future<void> loadAllArtists() async {
    loadAllCalls++;
  }

  @override
  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {
    value = value.copyWith(
      artistIds: artistIds,
      genres: genres,
      localArtistIds: localArtistIds,
      localGenres: localGenres,
    );
    saves.add(value);
  }
}

Finder _label(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data?.toLowerCase() == label.toLowerCase(),
);

Finder _checkbox(String title) => find.descendant(
  of: find.ancestor(of: _label(title), matching: find.byType(ObsidianHoverRow)),
  matching: find.byType(Checkbox),
);

bool _selected(WidgetTester tester, String title) =>
    tester.widget<Checkbox>(_checkbox(title)).value!;

Future<void> _tap(WidgetTester tester, String label) async {
  final target = const ['Server', 'Local', 'Artists', 'Genres'].contains(label)
      ? find.descendant(
          of: find.byWidgetPredicate((widget) => widget is TextButton),
          matching: _label(label),
        )
      : _label(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _ShuffleController controller, {
  Size size = const Size(1000, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ObsidianTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(
        controller: controller,
        child: const CustomShuffleSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(configureTestFonts);

  testWidgets(
    'genre labels capitalize mixed and saved metadata while keys stay lowercase',
    (tester) async {
      final controller = _ShuffleController(
        value: const CustomShuffleSettings(genres: ['alternative rock']),
      );
      controller._artists.first.genres
        ..clear()
        ..addAll(['ambient', 'edm', 'r&b']);
      controller._artists.last.genres
        ..clear()
        ..add('AMBIENT');
      await _mount(tester, controller);
      await _tap(tester, 'Genres');
      expect(find.text('Ambient'), findsOneWidget);
      expect(find.text('Alternative Rock'), findsOneWidget);
      expect(find.text('EDM'), findsOneWidget);
      expect(find.text('R&B'), findsOneWidget);
      await _tap(tester, 'EDM');
      await _save(tester);
      expect(controller.value.genres, containsAll(['alternative rock', 'edm']));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'artist and genre selections save independently for each source',
    (tester) async {
      final controller = _ShuffleController();
      await _mount(tester, controller);

      await tester.tap(_checkbox(_serverAlpha));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(controller.value.artistIds, ['shared-artist']);
      expect(controller.value.localArtistIds, isEmpty);

      await _tap(tester, 'Genres');
      await _tap(tester, 'Ambient');
      await _save(tester);
      expect(controller.value.genres, ['ambient']);

      await _tap(tester, 'Local');
      expect(_selected(tester, 'Ambient'), isFalse);
      await _tap(tester, 'Rock');
      await _tap(tester, 'Artists');
      expect(_selected(tester, _localAlpha), isFalse);
      await _tap(tester, _localAlpha);
      await _save(tester);
      expect(controller.value.artistIds, ['shared-artist']);
      expect(controller.value.genres, ['ambient']);
      expect(controller.value.localArtistIds, ['shared-artist']);
      expect(controller.value.localGenres, ['rock']);

      await _tap(tester, 'Server');
      expect(_selected(tester, _serverAlpha), isTrue);
      expect(_selected(tester, 'Beta artist'), isFalse);
      await _tap(tester, 'Genres');
      expect(_selected(tester, 'Ambient'), isTrue);
      expect(_selected(tester, 'Jazz'), isFalse);
      expect(controller.saves, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters rows while select all and clear keep other sources',
    (tester) async {
      final controller = _ShuffleController(
        value: const CustomShuffleSettings(
          localArtistIds: ['local-artist'],
          localGenres: ['rock'],
        ),
      );
      await _mount(tester, controller);

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();
      expect(_label(_serverAlpha), findsOneWidget);
      expect(_label('Beta artist'), findsNothing);
      await _tap(tester, 'Select all');
      await _save(tester);
      expect(controller.loadAllCalls, 1);
      expect(
        controller.value.artistIds,
        unorderedEquals(['shared-artist', 'server-artist']),
      );
      await _tap(tester, 'Clear');
      await _save(tester);
      expect(controller.value.artistIds, isEmpty);

      await _tap(tester, 'Genres');
      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();
      expect(_label('Jazz'), findsOneWidget);
      expect(_label('Ambient'), findsNothing);
      await _tap(tester, 'Select all');
      await _save(tester);
      expect(controller.value.genres, ['ambient', 'jazz']);
      await _tap(tester, 'Clear');
      await _save(tester);
      expect(controller.value.genres, isEmpty);
      expect(controller.value.localArtistIds, ['local-artist']);
      expect(controller.value.localGenres, ['rock']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local selections remain available without a server connection', (
    tester,
  ) async {
    final controller = _ShuffleController(authorized: false);
    await _mount(tester, controller);
    expect(_label('Connect to a server to load artists.'), findsOneWidget);

    await _tap(tester, 'Local');
    await _tap(tester, _localAlpha);
    await _save(tester);
    expect(controller.value.localArtistIds, ['shared-artist']);
    expect(controller.value.artistIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (
      name: 'narrow with larger text',
      size: const Size(320, 900),
      textScale: 1.4,
    ),
    (name: 'desktop', size: const Size(1440, 1000), textScale: 1.0),
  ]) {
    testWidgets('custom shuffle remains usable on ${layout.name}', (
      tester,
    ) async {
      final controller = _ShuffleController();
      final semantics = tester.ensureSemantics();
      try {
        await _mount(
          tester,
          controller,
          size: layout.size,
          textScale: layout.textScale,
        );
        expect(tester.takeException(), isNull);
        final title = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('CUSTOM SHUFFLE'),
            matching: find.byType(RichText),
          ),
        );
        expect(
          title.didExceedMaxLines,
          isFalse,
          reason: 'The full page title should remain visible.',
        );

        await _tap(tester, _serverAlpha);
        await _save(tester);
        expect(_selected(tester, _serverAlpha), isTrue);
        expect(
          tester.getSemantics(_checkbox(_serverAlpha)),
          containsSemantics(hasCheckedState: true, isChecked: true),
        );
        await _tap(tester, 'Genres');
        await _tap(tester, 'Local');
        await _tap(tester, 'Select all');
        await _save(tester);
        expect(controller.value.localGenres, ['ambient', 'rock']);
        await _tap(tester, 'Clear');
        await _save(tester);
        expect(controller.value.localGenres, isEmpty);
        await _tap(tester, 'Artists');
        expect(_label(_localAlpha), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

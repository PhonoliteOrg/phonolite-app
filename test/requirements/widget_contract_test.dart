import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/pages/settings/settings_page.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_manager_panel.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_cards.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_filter_chips.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_result_tile.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/expandable_summary_text.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/dismissible_selection_area.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_adaptive_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/collection_view_toggle_button.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import '../support/source_test_helpers.dart';
import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  group('widget contracts', () {
    test('display genre separators use a shared unicode bullet formatter', () {
      final source = [
        readProjectModule('lib/application/presentation/genre_labels.dart'),
        readProjectModule('lib/ui/shared/music/artists/artist_hero.dart'),
        readProjectModule('lib/ui/shared/music/albums/album_hero.dart'),
      ].join('\n');
      final mojibakeBullet = String.fromCharCodes([
        0x00C3,
        0x00A2,
        0x00E2,
        0x201A,
        0x00AC,
        0x00C2,
        0x00A2,
      ]);
      final latin1Bullet = String.fromCharCodes([0x00C2, 0x20AC, 0x00A2]);

      expectContainsAll(source, const [
        "join(' \\u2022 ')",
        'genreBulletLine(artist.genres)',
        'genreBulletLine(album.genres)',
      ]);
      expect(source, isNot(contains(mojibakeBullet)));
      expect(source, isNot(contains(latin1Bullet)));
    });

    test('now playing scrubbers hold local drag state during seeks', () {
      final source = readProjectFiles([
        'lib/ui/features/playback/widgets/now_playing_bar.dart',
        'lib/application/controllers/playback/playback_controls_controller.dart',
      ]);

      expectContainsAll(source, const [
        'class PlaybackCompactFooterRow extends PlaybackScrubber',
        'class PlaybackProgressBar extends PlaybackScrubber',
        'extends PlaybackScrubberState<PlaybackCompactFooterRow>',
        'extends PlaybackScrubberState<PlaybackProgressBar>',
        'abstract class PlaybackScrubberState<T extends PlaybackScrubber>',
        'Duration? _dragPosition;',
        'bool _isDragging = false;',
        "const int playbackScrubberAuthoritativeDiscontinuityMs = 1500;",
        "const int playbackScrubberMaxInterpolationLeadMs = 1500;",
        "Duration playbackBoundedScrubberDisplayPosition({",
        "final leadCeilingMs =\n      authoritativeMs + playbackScrubberMaxInterpolationLeadMs;",
        'final authoritativeDeltaMs =',
        'widget.position.inMilliseconds - oldWidget.position.inMilliseconds;',
        'authoritativeDeltaMs.abs() >=',
        "playbackScrubberAuthoritativeDiscontinuityMs",
        "playbackBoundedScrubberDisplayPosition(",
        'authoritativePosition: widget.position,',
        'if (_isDragging) {',
        'void beginDrag(double value)',
        'void updateDrag(double value)',
        'void endDrag(double value)',
        'widget.onSeekPreview(position);',
        'widget.onSeek(position);',
        'onChangeStart: widget.enabled ? beginDrag : null,',
        'onChanged: widget.enabled ? updateDrag : null,',
        'onChangeEnd: widget.enabled ? endDrag : null,',
      ]);
      expect(
        RegExp(r'Duration\? _dragPosition;').allMatches(source),
        hasLength(1),
      );
      expect(
        RegExp(r'bool _isDragging = false;').allMatches(source),
        hasLength(1),
      );
      expect(
        RegExp(
          r'onChangeStart: widget\.enabled \? beginDrag : null,',
        ).allMatches(source),
        hasLength(2),
      );
      expect(
        RegExp(r'final authoritativeDeltaMs =').allMatches(source),
        hasLength(1),
      );
      expect(
        RegExp(r'authoritativePosition: widget\.position,').allMatches(source),
        hasLength(2),
      );
      expect(source, isNot(contains('deltaMs >= 600')));
      expect(
        source,
        isNot(
          contains(
            'widget.position.inMilliseconds - _displayPosition.inMilliseconds',
          ),
        ),
      );
    });

    test('expanded now playing sheet uses glass with native mobile sizing', () {
      final source = readProjectFiles([
        'lib/ui/features/playback/widgets/now_playing_bar.dart',
        'lib/application/controllers/playback/playback_controls_controller.dart',
      ]);

      expectContainsAll(source, const [
        'if (usesSideNavigation(context)) {',
        "bool playbackUsesNativeMobileExpandedSheet(BuildContext context)",
        'platform == TargetPlatform.iOS || platform == TargetPlatform.android',
        'useSafeArea: useNativeMobileTreatment,',
        'barrierColor: Colors.black.withValues(alpha: 0.45)',
        'useNativeMobileTreatment ? size.height : size.height * 0.92',
        'final sheetBody = ObsidianGlassSurface(',
      ]);
    });

    test('local shuffle modal mirrors server shuffle modes', () {
      final source = readProjectFiles([
        'lib/ui/features/playback/widgets/now_playing_bar.dart',
        'lib/application/controllers/playback/playback_controls_controller.dart',
      ]).replaceAll(RegExp(r'\s+'), ' ');

      expectContainsAll(source, const [
        'const items = [',
        'ShuffleMode.artist,',
        'ShuffleMode.album,',
        'ShuffleMode.currentPlaylist,',
        'ShuffleMode.custom,',
        'settings.localArtistIds.isNotEmpty',
        'settings.localGenres.isNotEmpty',
        'ShuffleMode.artist || ShuffleMode.album => '
            'serverScope ? playback.track != null : localContextEnabled',
        'ShuffleMode.custom => serverScope ? customEnabled :',
        'downloadedEnabled && customEnabled',
      ]);
    });

    test('shuffle modal does not block on liked-state loads', () {
      final source = readProjectFiles([
        'lib/ui/features/playback/widgets/now_playing_bar.dart',
        'lib/application/controllers/playback/playback_controls_controller.dart',
      ]);

      expectContainsAll(source, const [
        'void warmShuffleLikedState(',
        'unawaited(',
        'controller.loadLocalLikedTracks()',
        'StreamBuilder<List<Track>>',
        'controller.localLikedStream',
      ]);
      expect(
        source,
        isNot(contains('await controller.loadLocalLikedTracks();')),
      );
      expect(source, isNot(contains('await controller.loadLikedTracks();')));
    });

    test('now playing source tags show playlist names for both scopes', () {
      final source = readProjectFiles([
        'lib/ui/features/playback/widgets/now_playing_bar.dart',
        'lib/application/controllers/playback/playback_controls_controller.dart',
      ]);

      expectContainsAll(source, const [
        "String? playbackQueueSourceLabel(PlaybackState state)",
        "PlaybackPlaylistSourceTag(",
        'isLocal: state.queueSource == PlaybackQueueSource.offline',
        'controller.localPlaylistsStream',
        'controller.playlistsStream',
        'case PlaybackQueueSource.offline:',
        'switch (state.localPlaybackSource)',
        'case LocalPlaybackSource.library:',
        'case LocalPlaybackSource.liked:',
        "return 'LIKED TRACKS';",
        'case LocalPlaybackSource.playlist:',
        'playlistId: state.queueSourcePlaylistId',
      ]);
      expect(source, isNot(contains("'SOURCE: PLAYLIST'")));
      expect(source, isNot(contains("'SOURCE: LOCAL LIBRARY'")));
    });

    testWidgets('search hud clears input and routes submit actions', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Boards');
      var submitted = 0;
      var cleared = 0;
      var changed = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          SearchHud(
            controller: controller,
            onSubmit: () => submitted += 1,
            onClear: () => cleared += 1,
            onChanged: () => changed += 1,
          ),
        ),
      );

      expect(find.text('Boards'), findsOneWidget);
      expect(find.byIcon(PhonoliteIcons.search), findsNothing);

      await tester.tap(find.byIcon(PhonoliteIcons.x));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, 1);

      await tester.enterText(find.byType(TextField), 'Boards of Canada');
      await tester.pump();

      expect(controller.text, 'Boards of Canada');
      expect(changed, 1);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submitted, 1);
    });

    testWidgets('search filter chips expose artist album and track filters', (
      tester,
    ) async {
      String? selected;

      await tester.pumpWidget(
        wrapInTestApp(
          SearchFilterChips(
            activeFilter: 'artist',
            onChanged: (value) => selected = value,
          ),
        ),
      );

      expect(find.text('ARTIST'), findsOneWidget);
      expect(find.text('ALBUM'), findsOneWidget);
      expect(find.text('TRACK'), findsOneWidget);

      await tester.tap(find.text('TRACK'));
      await tester.pumpAndSettle();

      expect(selected, 'track');
    });

    testWidgets('collection view toggle forwards taps', (tester) async {
      var tapped = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          CollectionViewToggleButton(
            isListView: true,
            onPressed: () => tapped += 1,
          ),
        ),
      );

      await tester.tap(find.byIcon(PhonoliteIcons.rows3));
      await tester.pumpAndSettle();

      expect(tapped, 1);
    });

    testWidgets('borderless tech button uses hud hover treatment', (
      tester,
    ) async {
      var tapped = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          TechButton(
            label: 'Download Artist',
            icon: PhonoliteIcons.download,
            chrome: TechButtonChrome.borderless,
            onTap: () => tapped += 1,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(TechButton),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );

      final label = find.text('DOWNLOAD ARTIST');
      expect(
        tester.widget<Text>(label).style?.color,
        ObsidianPalette.textMuted,
      );
      expect(
        tester.widget<Icon>(find.byIcon(PhonoliteIcons.download)).color,
        ObsidianPalette.textMuted,
      );

      tester
          .widget<MouseRegion>(
            find.descendant(
              of: find.byType(TechButton),
              matching: find.byType(MouseRegion),
            ),
          )
          .onEnter
          ?.call(const PointerEnterEvent());
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.widget<Text>(label).style?.color, ObsidianPalette.gold);
      expect(tester.widget<Text>(label).style?.shadows, isNotEmpty);
      final hoveredIcon = tester.widget<Icon>(
        find.byIcon(PhonoliteIcons.download),
      );
      expect(hoveredIcon.color, ObsidianPalette.gold);
      expect(hoveredIcon.shadows, isNotEmpty);

      await tester.tap(label);
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('icon-only tech button keeps label semantic-only', (
      tester,
    ) async {
      var tapped = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          TechButton(
            label: 'Download Artist',
            icon: PhonoliteIcons.download,
            iconOnly: true,
            tooltip: 'Download Artist',
            chrome: TechButtonChrome.borderless,
            onTap: () => tapped += 1,
          ),
        ),
      );

      expect(find.text('DOWNLOAD ARTIST'), findsNothing);
      expect(find.byIcon(PhonoliteIcons.download), findsOneWidget);
      expect(find.bySemanticsLabel('Download Artist'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(PhonoliteIcons.download)).size,
        24,
      );

      await tester.tap(find.byIcon(PhonoliteIcons.download));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('confirmation modal can use borderless action buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          const ConfirmationModal(
            title: 'Download artist',
            message: 'Queue downloads for Artist?',
            confirmLabel: 'Download',
            confirmVariant: TechButtonVariant.standard,
            actionChrome: TechButtonChrome.borderless,
          ),
        ),
      );

      expect(find.text('DOWNLOAD'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(
        find.descendant(
          of: find.bySubtype<AlertDialog>(),
          matching: find.byType(ModalActionButton),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.bySubtype<AlertDialog>(),
          matching: find.byType(TechButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.bySubtype<AlertDialog>(),
          matching: find.byType(TextButton),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(ModalActionButton),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );
    });

    testWidgets('overflow action menu shows disabled actions', (tester) async {
      var selected = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          ObsidianOverflowActionButton(
            tooltip: 'More actions',
            actions: [
              ObsidianMenuAction(
                label: 'Enabled action',
                icon: PhonoliteIcons.check,
                onTap: () => selected += 1,
              ),
              const ObsidianMenuAction(
                label: 'Disabled action',
                icon: Icons.block_rounded,
                onTap: null,
              ),
            ],
          ),
        ),
      );

      final menuButton = tester.widget<PopupMenuButton<int>>(
        find.byType(PopupMenuButton<int>),
      );
      expect(menuButton.popUpAnimationStyle, AnimationStyle.noAnimation);

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();

      expect(find.text('Enabled action'), findsOneWidget);
      expect(find.text('Disabled action'), findsOneWidget);

      await tester.tap(find.text('Disabled action'));
      await tester.pumpAndSettle();

      expect(selected, 0);

      await tester.tap(find.text('Enabled action'));
      await tester.pumpAndSettle();

      expect(selected, 1);

      await tester.pumpWidget(
        wrapInTestApp(
          const ObsidianOverflowActionButton(
            tooltip: 'No actions',
            actions: [
              ObsidianMenuAction(
                label: 'Unavailable',
                icon: Icons.block_rounded,
                onTap: null,
              ),
            ],
          ),
        ),
      );

      expect(find.byTooltip('No actions'), findsOneWidget);
      expect(find.byType(PopupMenuButton<int>), findsNothing);
    });

    testWidgets(
      'expandable summary text toggles between collapsed and expanded',
      (tester) async {
        final text = List.filled(40, 'summary').join(' ');

        await tester.pumpWidget(
          wrapInTestApp(
            ExpandableSummaryText(
              text: text,
              style: const TextStyle(color: Colors.white),
              toggleColor: Colors.amber,
              toggleThreshold: 20,
              collapsedMaxHeight: 20,
            ),
          ),
        );

        expect(find.text('Read more'), findsOneWidget);
        expect(find.text('Collapse'), findsNothing);

        await tester.tap(find.text('Read more'));
        await tester.pumpAndSettle();

        expect(find.text('Collapse'), findsOneWidget);
      },
    );

    testWidgets(
      'dismissible selection area clears selected text on later tap',
      (tester) async {
        String? selectedText;

        await tester.pumpWidget(
          SelectionDismissLayer(
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DismissibleSelectionArea(
                      onSelectionChanged: (content) {
                        selectedText = content?.plainText;
                      },
                      child: const Text('selectable artist bio text'),
                    ),
                    const SizedBox(
                      key: Key('selection-dismiss-target'),
                      width: 240,
                      height: 80,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final textRect = tester.getRect(
          find.text('selectable artist bio text'),
        );
        final gesture = await tester.startGesture(
          textRect.centerLeft + const Offset(2, 0),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await gesture.moveTo(textRect.centerRight - const Offset(2, 0));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(selectedText, isNotNull);

        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('selection-dismiss-target'))),
        );
        await tester.pump();
        await tester.pump();

        expect(selectedText, isNull);
      },
    );

    testWidgets('dismissible selection area ignores the selecting drag', (
      tester,
    ) async {
      String? selectedText;

      await tester.pumpWidget(
        SelectionDismissLayer(
          child: MaterialApp(
            home: Scaffold(
              body: DismissibleSelectionArea(
                onSelectionChanged: (content) {
                  selectedText = content?.plainText;
                },
                child: const Text('selectable album tag text'),
              ),
            ),
          ),
        ),
      );

      final textRect = tester.getRect(find.text('selectable album tag text'));
      final gesture = await tester.startGesture(
        textRect.centerLeft + const Offset(2, 0),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await gesture.moveTo(textRect.centerRight - const Offset(2, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selectedText, isNotNull);
    });

    testWidgets(
      'dismissible selection area does not clear on drag after selection',
      (tester) async {
        String? selectedText;

        await tester.pumpWidget(
          SelectionDismissLayer(
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DismissibleSelectionArea(
                      onSelectionChanged: (content) {
                        selectedText = content?.plainText;
                      },
                      child: const Text('selectable artist tags text'),
                    ),
                    const SizedBox(
                      key: Key('selection-drag-target'),
                      width: 240,
                      height: 80,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final textRect = tester.getRect(
          find.text('selectable artist tags text'),
        );
        final selectionGesture = await tester.startGesture(
          textRect.centerLeft + const Offset(2, 0),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await selectionGesture.moveTo(
          textRect.centerRight - const Offset(2, 0),
        );
        await selectionGesture.up();
        await tester.pumpAndSettle();

        expect(selectedText, isNotNull);

        final dragTarget = tester.getRect(
          find.byKey(const Key('selection-drag-target')),
        );
        final dragGesture = await tester.startGesture(
          dragTarget.centerLeft + const Offset(2, 0),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await dragGesture.moveTo(dragTarget.centerRight - const Offset(2, 0));
        await dragGesture.up();
        await tester.pump();
        await tester.pump();

        expect(selectedText, isNotNull);
      },
    );

    testWidgets('playlist editor clamps names and saves trimmed values', (
      tester,
    ) async {
      String? savedName;

      await tester.pumpWidget(
        wrapInTestApp(
          PlaylistEditorModal(
            title: 'Rename playlist',
            initialValue: '',
            onSubmit: (value, _, _, _) => savedName = value,
          ),
        ),
      );

      await tester.enterText(
        find.byType(TextField).first,
        '  A very long playlist name that should be clamped  ',
      );
      await tester.pumpAndSettle();

      expect(find.text('32/32'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PlaylistEditorModal),
          matching: find.byType(ModalActionButton),
        ),
        findsNWidgets(2),
      );
      expect(find.text('LOCAL'), findsNothing);
      expect(find.text('SERVER'), findsNothing);

      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(savedName, isNotNull);
      expect(savedName!.length, lessThanOrEqualTo(32));
      expect(savedName, savedName!.trim());
    });

    testWidgets('playlist creation editor can choose local or server target', (
      tester,
    ) async {
      PlaylistEditorTarget? savedTarget;

      await tester.pumpWidget(
        wrapInTestApp(
          PlaylistEditorModal(
            title: 'Create playlist',
            initialValue: '',
            showTargetSelector: true,
            onSubmit: (_, _, _, target) => savedTarget = target,
          ),
        ),
      );

      expect(find.text('LOCAL'), findsOneWidget);
      expect(find.text('SERVER'), findsOneWidget);

      await tester.tap(find.text('SERVER'));
      await tester.enterText(find.byType(TextField).first, 'Server Mix');
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(savedTarget, PlaylistEditorTarget.server);
    });

    testWidgets('playlist editor mobile keyboard actions dismiss editing', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          PlaylistEditorModal(
            title: 'Create playlist',
            initialValue: '',
            onSubmit: (_, _, _, _) {},
          ),
        ),
      );

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList(growable: false);
      expect(fields, hasLength(2));
      expect(fields[0].textInputAction, TextInputAction.done);
      expect(fields[1].textInputAction, TextInputAction.done);
      expect(fields[1].keyboardType, TextInputType.multiline);
      expect(fields[0].onSubmitted, isNotNull);
      expect(fields[1].onSubmitted, isNotNull);
    });

    test('playlist editor uses mobile photo picker and byte MIME fallback', () {
      final pickerSource = readProjectModule(
        'lib/infrastructure/platform/files/playlist_image_file_picker.dart',
      );
      final editorSource = readProjectFiles([
        'lib/ui/features/playlists/widgets/playlist_editor_modal.dart',
        'lib/application/controllers/playlists/playlist_editor_controller.dart',
      ]);

      expectContainsAll(pickerSource, const [
        "import 'package:image_picker/image_picker.dart' as image_picker;",
        'bool get _usePhotoLibraryPicker',
        'TargetPlatform.android || TargetPlatform.iOS => true',
        'image_picker.ImagePicker().pickImage(',
        'source: image_picker.ImageSource.gallery',
        'return await openFile(acceptedTypeGroups: acceptedTypeGroups);',
      ]);
      expectContainsAll(editorSource, const [
        'final contentType = contentTypeForFile(file, bytes);',
        'file.mimeType?.split',
        'String contentTypeForBytes(Uint8List bytes)',
        "return 'image/jpeg';",
        "return 'image/png';",
        "return 'image/webp';",
      ]);
    });

    testWidgets('add to playlist modal filters, adds, and removes tracks', (
      tester,
    ) async {
      final selectedIds = <String>[];
      final removedIds = <String>[];
      final playlists = <Playlist>[
        Playlist(id: 'focus', name: 'Deep Focus', trackIds: const <String>[]),
        Playlist(
          id: 'liked',
          name: 'Liked Mix',
          trackIds: const <String>['t1'],
        ),
      ];

      await tester.pumpWidget(
        wrapInTestApp(
          AddToPlaylistModal(
            scope: ActionScope.local,
            playlists: playlists,
            trackId: 't1',
            canUsePlaylists: true,
            onSelected: (playlist) => selectedIds.add(playlist.id),
            onRemoved: (playlist) => removedIds.add(playlist.id),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'focus');
      await tester.pumpAndSettle();

      expect(find.text('Deep Focus'), findsOneWidget);
      expect(find.text('Liked Mix'), findsNothing);

      await tester.tap(find.text('Deep Focus'));
      await tester.pumpAndSettle();

      expect(selectedIds, <String>['focus']);
      expect(find.textContaining('1 tracks'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'liked');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(PhonoliteIcons.trash2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YES'));
      await tester.pumpAndSettle();

      expect(removedIds, <String>['liked']);
    });

    testWidgets('desktop track row renders track metadata and controls', (
      tester,
    ) async {
      _setViewport(tester, const Size(1280, 800));
      final track = Track(
        id: 'track-1',
        title: 'Dayvan Cowboy',
        artist: 'Boards of Canada',
        album: 'The Campfire Headphase',
        durationMs: 321000,
        liked: true,
        inPlaylists: false,
      );

      await tester.pumpWidget(
        wrapInTestApp(
          TrackRowTile(
            track: track,
            index: 2,
            onTap: () {},
            onAddToPlaylist: () {},
            onLike: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.text('Dayvan Cowboy'), findsOneWidget);
      expect(find.textContaining('Boards of Canada'), findsOneWidget);
      expect(find.text('05:21'), findsOneWidget);
      expect(find.byType(PlaylistAddIcon), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgAssetIcon &&
              widget.assetName == 'assets/icons/lucide/heart-filled.svg',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(PhonoliteIcons.trash2), findsOneWidget);
    });

    testWidgets('compact track row puts all actions in the shared modal', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 800));
      final track = Track(
        id: 'track-1',
        title: 'A very long track title that should remain readable',
        artist: 'Boards of Canada',
        album: 'The Campfire Headphase',
        durationMs: 321000,
        liked: false,
        inPlaylists: false,
      );
      var downloaded = 0;
      var added = 0;
      var liked = 0;
      var deleted = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          Align(
            alignment: Alignment.topCenter,
            child: TrackRowTile(
              track: track,
              index: 2,
              onTap: () {},
              onDownload: () => downloaded += 1,
              showAlbumArt: true,
              onAddToPlaylist: () => added += 1,
              onLike: () => liked += 1,
              onDelete: () => deleted += 1,
            ),
          ),
        ),
      );

      expect(find.text('05:21'), findsNothing);
      expect(find.byIcon(PhonoliteIcons.download), findsNothing);
      expect(find.byIcon(PhonoliteIcons.heart), findsNothing);
      expect(find.byType(PlaylistAddIcon), findsNothing);
      expect(find.byIcon(PhonoliteIcons.trash2), findsNothing);
      expect(find.byTooltip('Track actions'), findsOneWidget);
      expect(
        tester.getSize(find.byType(TrackRowTile)).height,
        lessThanOrEqualTo(56),
      );
      expect(tester.widget<Text>(find.text(track.title)).style?.fontSize, 13);
      expect(
        tester
            .widget<Text>(find.textContaining('Boards of Canada'))
            .style
            ?.fontSize,
        11,
      );
      expect(find.byType(LikeIconButton), findsNothing);
      expect(
        tester.getSize(find.byTooltip('Track actions')),
        const Size.square(44),
      );
      for (final action in ['Download', 'Like', 'Add to playlist']) {
        await tester.tap(find.byTooltip('Track actions'));
        await tester.pumpAndSettle();
        expect(find.byType(ObsidianAlertDialog), findsOneWidget);
        expect(find.byType(PopupMenuItem<int>), findsNothing);
        expect(find.text('Delete'), findsOneWidget);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(find.byType(ObsidianAlertDialog), findsNothing);
      }
      expect(downloaded, 1);
      expect(liked, 1);
      expect(added, 1);
      expect(deleted, 0);
    });

    testWidgets('compact collection rows use ellipsizing mobile text', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 800));
      const longAlbumTitle =
          'An album title long enough to require ellipsis on mobile';
      const longArtistName =
          'An artist name long enough to require ellipsis on mobile';
      const longSearchTitle =
          'A search result long enough to require ellipsis on mobile';

      await tester.pumpWidget(
        wrapInTestApp(
          Column(
            children: [
              AlbumRowTile(
                album: Album(
                  id: 'album-1',
                  title: longAlbumTitle,
                  artist: 'Artist',
                  artistId: 'artist-1',
                  trackCount: 10,
                ),
                coverUrl: '',
                headers: const <String, String>{},
              ),
              ArtistRowTile(
                artist: Artist(
                  id: 'artist-1',
                  name: longArtistName,
                  albumCount: 4,
                ),
                coverUrl: null,
                headers: const <String, String>{},
              ),
              SearchResultTile(
                result: SearchResult(
                  kind: 'track',
                  id: 'track-1',
                  title: longSearchTitle,
                  subtitle: 'Subtitle long enough to ellipsize on mobile',
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      for (final label in [longAlbumTitle, longArtistName, longSearchTitle]) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.style?.fontSize, 14.5);
      }
    });

    testWidgets('downloaded track row exposes remove download action', (
      tester,
    ) async {
      _setViewport(tester, const Size(1280, 800));
      final track = Track(
        id: 'track-1',
        title: 'Dayvan Cowboy',
        artist: 'Boards of Canada',
        album: 'The Campfire Headphase',
        durationMs: 321000,
        liked: false,
        inPlaylists: false,
      );
      var removed = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          TrackRowTile(
            track: track,
            index: 1,
            offlineDownload: _download(
              'track-1',
              OfflineDownloadStatus.downloaded,
            ),
            onRemoveDownload: () => removed += 1,
          ),
        ),
      );

      expect(find.byTooltip('Remove download'), findsOneWidget);
      expect(find.byIcon(PhonoliteIcons.trash2), findsOneWidget);
      expect(find.byIcon(PhonoliteIcons.circleCheck), findsNothing);
      await tester.tap(find.byTooltip('Remove download'));
      await tester.pump();

      expect(removed, 1);
    });

    testWidgets('track row selection mode toggles checkbox action', (
      tester,
    ) async {
      final track = Track(
        id: 'track-1',
        title: 'Dayvan Cowboy',
        artist: 'Boards of Canada',
        album: 'The Campfire Headphase',
        durationMs: 321000,
        liked: false,
        inPlaylists: false,
      );
      var toggled = 0;

      await tester.pumpWidget(
        wrapInTestApp(
          TrackRowTile(
            track: track,
            index: 1,
            selectionMode: true,
            selected: false,
            onSelectionToggle: () => toggled += 1,
            offlineDownload: _download(
              'track-1',
              OfflineDownloadStatus.downloaded,
            ),
            onRemoveDownload: () {},
          ),
        ),
      );

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.byTooltip('Remove download'), findsNothing);

      await tester.tap(find.text('Dayvan Cowboy'));
      await tester.pump();

      expect(toggled, 1);
    });

    testWidgets('download selection toolbar disables remove until selected', (
      tester,
    ) async {
      var removed = 0;
      var selectedAll = 0;
      var deselectedAll = 0;
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadSelectionToolbar(
            selectedCount: 0,
            totalCount: 3,
            onCancel: () {},
            onSelectAll: () => selectedAll += 1,
            onDeselectAll: () => deselectedAll += 1,
            onRemove: () => removed += 1,
          ),
        ),
      );

      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.byTooltip('Select all'), findsOneWidget);
      expect(find.byTooltip('Deselect all'), findsNothing);
      expect(find.text('SELECT ALL'), findsOneWidget);
      expect(find.text('DESELECT ALL'), findsNothing);
      expect(find.text('0 selected / 3 available'), findsNothing);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(find.byIcon(Icons.deselect_rounded), findsNothing);
      expect(find.text('REMOVE'), findsNothing);
      expect(find.byTooltip('Remove selected'), findsOneWidget);
      final selectAllLabel = find.descendant(
        of: find.byType(TextButton),
        matching: find.text('SELECT ALL'),
      );
      final selectText = tester.widget<Text>(selectAllLabel);
      expect(selectText.style, isNull);

      final selectButton = tester.widget<TextButton>(find.byType(TextButton));
      final selectStyle = selectButton.style?.textStyle?.resolve(
        const <WidgetState>{},
      );
      expect(
        selectButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
        ObsidianPalette.textMuted,
      );
      expect(selectStyle?.fontFamily, contains('Rajdhani'));
      expect(selectStyle?.fontSize, 14);
      expect(selectStyle?.fontWeight, FontWeight.w700);
      expect(
        selectButton.style?.foregroundColor?.resolve(const {
          WidgetState.hovered,
        }),
        ObsidianPalette.gold,
      );
      expect(
        selectButton.style?.textStyle?.resolve(const {
          WidgetState.hovered,
        })?.shadows,
        isNotEmpty,
      );

      await tester.tap(selectAllLabel);
      await tester.pump();

      expect(selectedAll, 1);
      expect(deselectedAll, 0);

      await tester.tap(find.byIcon(PhonoliteIcons.trash2));
      await tester.pump();

      expect(removed, 0);

      await tester.pumpWidget(
        wrapInTestApp(
          DownloadSelectionToolbar(
            selectedCount: 3,
            totalCount: 3,
            onCancel: () {},
            onSelectAll: () => selectedAll += 1,
            onDeselectAll: () => deselectedAll += 1,
            onRemove: () => removed += 1,
          ),
        ),
      );

      expect(find.byTooltip('Select all'), findsNothing);
      expect(find.byTooltip('Deselect all'), findsOneWidget);
      expect(find.text('SELECT ALL'), findsNothing);
      expect(find.text('DESELECT ALL'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(find.byIcon(Icons.deselect_rounded), findsNothing);
      expect(find.text('REMOVE'), findsNothing);
      expect(find.byTooltip('Remove selected'), findsOneWidget);
      final deselectAllLabel = find.descendant(
        of: find.byType(TextButton),
        matching: find.text('DESELECT ALL'),
      );
      final deselectText = tester.widget<Text>(deselectAllLabel);
      expect(deselectText.style, isNull);
      final deselectButton = tester.widget<TextButton>(find.byType(TextButton));
      final deselectStyle = deselectButton.style?.textStyle?.resolve(
        const <WidgetState>{},
      );
      expect(
        deselectButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
        ObsidianPalette.gold,
      );
      expect(deselectStyle?.fontFamily, contains('Rajdhani'));
      expect(deselectStyle?.fontSize, 14);
      expect(deselectStyle?.fontWeight, FontWeight.w700);

      await tester.tap(deselectAllLabel);
      await tester.pump();

      expect(selectedAll, 1);
      expect(deselectedAll, 1);

      await tester.tap(find.byIcon(PhonoliteIcons.trash2));
      await tester.pump();

      expect(removed, 1);

      await tester.pumpWidget(
        wrapInTestApp(
          DownloadSelectionToolbar(
            selectedCount: 0,
            totalCount: 0,
            onCancel: () {},
            onSelectAll: () => selectedAll += 1,
            onDeselectAll: () => deselectedAll += 1,
            onRemove: () => removed += 1,
          ),
        ),
      );

      final disabledSelectAllLabel = find.descendant(
        of: find.byType(TextButton),
        matching: find.text('SELECT ALL'),
      );
      expect(tester.widget<Text>(disabledSelectAllLabel).style, isNull);
      final disabledSelectButton = tester.widget<TextButton>(
        find.byType(TextButton),
      );
      expect(
        disabledSelectButton.style?.foregroundColor?.resolve(const {
          WidgetState.disabled,
        }),
        ObsidianPalette.textMuted.withValues(alpha: 0.6),
      );
    });

    testWidgets('stats cards render selectors and summary modules', (
      tester,
    ) async {
      final stats = StatsResponse(
        year: 2026,
        month: null,
        totalMinutes: 250,
        topArtists: <StatsItem>[
          StatsItem(id: 'artist-1', name: 'Aphex Twin', minutes: 120),
        ],
        topTracks: <StatsTrack>[
          StatsTrack(
            id: 'track-1',
            title: 'Xtal',
            artist: 'Aphex Twin',
            minutes: 12,
            plays: 3,
          ),
        ],
        topGenres: <StatsItem>[
          StatsItem(id: 'ambient', name: 'Ambient', minutes: 60),
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

      expect(find.text('LISTENING STATISTICS'), findsOneWidget);
      expect(find.text('ALL MONTHS'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('TOTAL PLAYTIME'), findsOneWidget);
      expect(find.text('TOP GENRES'), findsOneWidget);
      expect(find.text('MOST PLAYED TRACKS'), findsOneWidget);
      expect(find.text('Xtal'), findsOneWidget);
    });

    testWidgets('download manager panel renders grouped states and actions', (
      tester,
    ) async {
      _setViewport(tester, const Size(900, 900));
      final downloads = <OfflineTrackDownload>[
        _download('queued', OfflineDownloadStatus.queued),
        _download('paused', OfflineDownloadStatus.paused),
        _download('failed', OfflineDownloadStatus.corrupt),
        _download('cached', OfflineDownloadStatus.downloaded),
      ];

      await tester.pumpWidget(
        wrapInTestApp(DownloadManagerPanel(downloadsOverride: downloads)),
      );

      expect(find.text('Download Manager'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Needs Attention'), findsOneWidget);
      expect(find.byTooltip('Pause all'), findsOneWidget);
      expect(find.byTooltip('Resume paused'), findsOneWidget);
      expect(find.byTooltip('Clear all jobs and cache'), findsOneWidget);
      expect(find.text('CLEAR PAUSED / CACHED'), findsNothing);
      final managerPanel = find.byType(DownloadManagerPanel);
      expect(
        find.descendant(of: managerPanel, matching: find.byType(TextButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: managerPanel, matching: find.byType(TechButton)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: managerPanel,
          matching: find.byType(AnimatedContainer),
        ),
        findsWidgets,
      );
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byTooltip('Resume'), findsNothing);
      expect(find.byTooltip('Retry'), findsWidgets);
      expect(find.byTooltip('Cancel'), findsNothing);
      expect(find.byTooltip('Remove partial cache'), findsNothing);
      expect(find.text('Track cached'), findsNothing);
      expect(find.text('Downloaded / Cached'), findsNothing);
      expect(find.byTooltip('Remove download'), findsNothing);
      for (final status in ['QUEUED', 'PAUSED', 'CORRUPT']) {
        expect(find.textContaining(status), findsNothing);
      }
    });

    testWidgets(
      'download manager hides completed cached tracks from the queue',
      (tester) async {
        _setViewport(tester, const Size(900, 900));
        final downloads = <OfflineTrackDownload>[
          _download('cached', OfflineDownloadStatus.downloaded),
        ];

        await tester.pumpWidget(
          wrapInTestApp(DownloadManagerPanel(downloadsOverride: downloads)),
        );

        expect(find.text('Track cached'), findsNothing);
        expect(find.byTooltip('Pause all'), findsOneWidget);
        expect(find.byTooltip('Resume paused'), findsOneWidget);
        expect(find.byTooltip('Clear all jobs and cache'), findsOneWidget);
        expect(find.text('No queued downloads'), findsOneWidget);
      },
    );

    testWidgets('download manager mobile shell uses compact modal chrome', (
      tester,
    ) async {
      _setViewport(tester, const Size(390, 844));
      final downloads = <OfflineTrackDownload>[
        _download('queued', OfflineDownloadStatus.queued),
        _download('paused', OfflineDownloadStatus.paused),
        _download('failed', OfflineDownloadStatus.corrupt),
      ];

      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: downloads,
            jobsOverride: <OfflineDownloadJob>[
              _job('artist-active', 'artist', OfflineDownloadStatus.queued),
            ],
            presentation: ObsidianAdaptiveModalPresentation.dialog,
          ),
        ),
      );

      expect(find.text('Download Manager'), findsOneWidget);
      expect(find.text('CLOSE'), findsOneWidget);
      expect(find.byTooltip('Pause all'), findsOneWidget);
      expect(find.byTooltip('Resume paused'), findsOneWidget);
      expect(find.byTooltip('Clear all jobs and cache'), findsOneWidget);
      expect(find.text('PAUSE ALL'), findsNothing);
      expect(find.text('RESUME PAUSED'), findsNothing);
      expect(find.text('CLEAR ALL JOBS AND CACHE'), findsNothing);
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Needs Attention'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('download manager panel sorts the live queue', (tester) async {
      _setViewport(tester, const Size(1280, 900));
      final downloads = <OfflineTrackDownload>[
        _download(
          'queued-low',
          OfflineDownloadStatus.queued,
          priority: 1,
          createdAtMs: 10,
        ),
        _download(
          'queued-high-new',
          OfflineDownloadStatus.queued,
          priority: 5,
          createdAtMs: 30,
        ),
        _download(
          'active',
          OfflineDownloadStatus.downloading,
          priority: 0,
          createdAtMs: 40,
        ),
        _download(
          'queued-high-old',
          OfflineDownloadStatus.queued,
          priority: 5,
          createdAtMs: 20,
        ),
      ];

      await tester.pumpWidget(
        wrapInTestApp(DownloadManagerPanel(downloadsOverride: downloads)),
      );

      final activeTop = tester.getTopLeft(find.text('Track active')).dy;
      final highOldTop = tester
          .getTopLeft(find.text('Track queued-high-old'))
          .dy;
      final highNewTop = tester
          .getTopLeft(find.text('Track queued-high-new'))
          .dy;
      final lowTop = tester.getTopLeft(find.text('Track queued-low')).dy;

      expect(activeTop, lessThan(highOldTop));
      expect(highOldTop, lessThan(highNewTop));
      expect(highNewTop, lessThan(lowTop));
    });

    testWidgets('download manager keeps track row actions stable', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: <OfflineTrackDownload>[
              _download('queued', OfflineDownloadStatus.queued),
              _download('active', OfflineDownloadStatus.downloading),
            ],
          ),
        ),
      );

      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byTooltip('Resume'), findsNothing);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byTooltip('Cancel'), findsNothing);
      expect(find.byTooltip('Remove partial cache'), findsNothing);
      expect(find.byTooltip('Remove download'), findsNothing);
    });

    testWidgets('queued download row has no per-track controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: <OfflineTrackDownload>[
              _download('queued', OfflineDownloadStatus.queued),
            ],
          ),
        ),
      );

      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byTooltip('Resume'), findsNothing);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byTooltip('Cancel'), findsNothing);
      expect(find.byTooltip('Remove partial cache'), findsNothing);
      expect(find.byTooltip('Remove download'), findsNothing);
    });

    testWidgets('artist rolling job shows pause while active or queued', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: const <OfflineTrackDownload>[],
            jobsOverride: <OfflineDownloadJob>[
              _job(
                'artist-active',
                'artist',
                OfflineDownloadStatus.downloading,
              ),
              _job('artist-queued', 'artist', OfflineDownloadStatus.queued),
            ],
          ),
        ),
      );

      expect(find.byTooltip('Pause download job'), findsNWidgets(2));
      expect(find.byTooltip('Resume download job'), findsNothing);
      expect(find.byTooltip('Cancel and remove job'), findsNWidgets(2));
    });

    testWidgets('paused artist rolling job shows resume', (tester) async {
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: const <OfflineTrackDownload>[],
            jobsOverride: <OfflineDownloadJob>[
              _job('artist-paused', 'artist', OfflineDownloadStatus.paused),
            ],
          ),
        ),
      );

      expect(find.byTooltip('Resume download job'), findsOneWidget);
      expect(find.byTooltip('Pause download job'), findsNothing);
      expect(find.byTooltip('Cancel and remove job'), findsOneWidget);
      expect(find.byTooltip('Pause all'), findsOneWidget);
      expect(find.byTooltip('Resume paused'), findsOneWidget);
      expect(find.byTooltip('Clear all jobs and cache'), findsOneWidget);
    });

    testWidgets('non-artist rolling jobs show downloader controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: const <OfflineTrackDownload>[],
            jobsOverride: <OfflineDownloadJob>[
              _job('album-active', 'album', OfflineDownloadStatus.downloading),
            ],
          ),
        ),
      );

      expect(find.byTooltip('Pause download job'), findsOneWidget);
      expect(find.byTooltip('Resume download job'), findsNothing);
      expect(find.byTooltip('Cancel and remove job'), findsOneWidget);
    });

    testWidgets('empty state widgets render title and message', (tester) async {
      await tester.pumpWidget(
        wrapInTestApp(
          const EmptyState(
            title: 'No tracks',
            message: 'Pick another album to see tracks.',
          ),
        ),
      );

      expect(find.text('No tracks'), findsOneWidget);
      expect(find.text('Pick another album to see tracks.'), findsOneWidget);
    });

    testWidgets(
      'settings page hides storage paths on mobile',
      (tester) async {
        _setViewport(tester, const Size(900, 900));
        await tester.pumpWidget(
          _buildOfflineStorageSectionTestApp(
            platform: defaultTargetPlatform,
            child: const OfflineStorageSection(
              locations: OfflineStorageLocations(
                metadataDirectory: '/app/Phonolite/offline',
                downloadsDirectory: '/app/Phonolite/offline',
                metadataDirectoryIsDefault: true,
                downloadsDirectoryIsDefault: true,
              ),
              onChangeMetadata: null,
              onResetMetadata: null,
              onChangeDownloads: null,
              onResetDownloads: null,
              onResetOfflineData: null,
              logsLocation: LogStorageLocation(
                directory: '/app/Phonolite/logs',
                isDefault: true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Metadata database'), findsNothing);
        expect(find.text('Downloaded audio'), findsNothing);
        expect(find.text('Logs storage'), findsNothing);
        expect(find.textContaining('/app/Phonolite'), findsNothing);
        expect(find.text('Reset local data'), findsOneWidget);
        expect(find.text('CHANGE'), findsNothing);
        expect(find.text('RESET PATH'), findsNothing);
        expect(find.text('OPEN FOLDER'), findsNothing);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      testWidgets('settings page opens each storage folder on $platform', (
        tester,
      ) async {
        _setViewport(tester, const Size(1280, 900));
        var metadataOpened = 0;
        var downloadsOpened = 0;
        var logsOpened = 0;
        var logsChanged = 0;
        var logsReset = 0;
        await tester.pumpWidget(
          _buildOfflineStorageSectionTestApp(
            platform: platform,
            child: OfflineStorageSection(
              locations: const OfflineStorageLocations(
                metadataDirectory: '/app/Phonolite/offline',
                downloadsDirectory: '/app/Phonolite/offline',
                metadataDirectoryIsDefault: true,
                downloadsDirectoryIsDefault: true,
              ),
              onChangeMetadata: _noop,
              onResetMetadata: _noop,
              onChangeDownloads: _noop,
              onResetDownloads: _noop,
              onResetOfflineData: _noop,
              onOpenMetadata: () => metadataOpened++,
              onOpenDownloads: () => downloadsOpened++,
              logsLocation: const LogStorageLocation(
                directory: '/app/Phonolite/logs',
                isDefault: true,
              ),
              onChangeLogs: () => logsChanged++,
              onResetLogs: () => logsReset++,
              onOpenLogs: () => logsOpened++,
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text(
            'Folder selection and custom paths are not supported on iPhone or iPad.',
          ),
          findsNothing,
        );
        expect(
          find.textContaining('Managed automatically on this device -'),
          findsNothing,
        );
        expect(find.text('Logs storage'), findsOneWidget);
        expect(find.text('Reset local data'), findsOneWidget);
        expect(find.text('Reset offline data'), findsNothing);
        expect(find.text('CHANGE'), findsNWidgets(3));
        expect(find.text('RESET PATH'), findsNWidgets(3));
        expect(find.text('OPEN FOLDER'), findsNWidgets(3));
        await tester.tap(find.text('OPEN FOLDER').first);
        expect(metadataOpened, 1);
        expect(downloadsOpened, 0);
        await tester.tap(find.text('OPEN FOLDER').at(1));
        expect(metadataOpened, 1);
        expect(downloadsOpened, 1);
        await tester.tap(find.text('OPEN FOLDER').last);
        await tester.tap(find.text('CHANGE').last);
        await tester.tap(find.text('RESET PATH').last);
        expect(logsOpened, 1);
        expect(logsChanged, 1);
        expect(logsReset, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'narrow desktop storage menu opens each folder on $platform',
        (tester) async {
          _setViewport(tester, const Size(390, 844));
          var metadataOpened = 0;
          var downloadsOpened = 0;
          var logsOpened = 0;
          await tester.pumpWidget(
            _buildOfflineStorageSectionTestApp(
              platform: platform,
              child: OfflineStorageSection(
                locations: const OfflineStorageLocations(
                  metadataDirectory: '/app/metadata',
                  downloadsDirectory: '/app/downloads',
                  metadataDirectoryIsDefault: false,
                  downloadsDirectoryIsDefault: false,
                ),
                onChangeMetadata: _noop,
                onResetMetadata: _noop,
                onChangeDownloads: _noop,
                onResetDownloads: _noop,
                onResetOfflineData: _noop,
                onOpenMetadata: () => metadataOpened++,
                onOpenDownloads: () => downloadsOpened++,
                logsLocation: const LogStorageLocation(
                  directory: '/app/logs',
                  isDefault: false,
                ),
                onChangeLogs: _noop,
                onResetLogs: _noop,
                onOpenLogs: () => logsOpened++,
              ),
            ),
          );
          await tester.pump();
          for (var row = 0; row < 3; row++) {
            await tester.tap(find.byTooltip('Storage actions').at(row));
            await tester.pumpAndSettle();
            expect(find.text('Open folder'), findsOneWidget);
            await tester.tap(find.text('Open folder'));
            await tester.pumpAndSettle();
          }
          expect(metadataOpened, 1);
          expect(downloadsOpened, 1);
          expect(logsOpened, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Android hides storage paths while locations are loading', (
      tester,
    ) async {
      _setViewport(tester, const Size(1280, 900));
      await tester.pumpWidget(
        _buildOfflineStorageSectionTestApp(
          platform: TargetPlatform.android,
          child: OfflineStorageSection(
            locations: null,
            onChangeMetadata: _noop,
            onResetMetadata: _noop,
            onChangeDownloads: _noop,
            onResetDownloads: _noop,
            onResetOfflineData: _noop,
            onOpenMetadata: _noop,
            onOpenDownloads: _noop,
          ),
        ),
      );
      expect(find.text('CHANGE'), findsNothing);
      expect(find.text('RESET PATH'), findsNothing);
      expect(find.text('OPEN FOLDER'), findsNothing);
      expect(find.text('Metadata database'), findsNothing);
      expect(find.text('Downloaded audio'), findsNothing);
      expect(find.text('Logs storage'), findsNothing);
      expect(find.text('Loading storage path'), findsNothing);
      expect(find.text('Reset local data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

OfflineTrackDownload _download(
  String id,
  OfflineDownloadStatus status, {
  int priority = 0,
  int createdAtMs = 1,
  int updatedAtMs = 2,
}) {
  return OfflineTrackDownload(
    serverBaseUrl: 'http://server.test/api',
    track: Track(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 120000,
      liked: false,
      inPlaylists: false,
    ),
    status: status,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    bytesDownloaded: status == OfflineDownloadStatus.downloaded ? 3 : 1,
    bytesTotal: 3,
    priority: priority,
  );
}

OfflineDownloadJob _job(String id, String kind, OfflineDownloadStatus status) {
  return OfflineDownloadJob(
    jobId: id,
    kind: kind,
    serverBaseUrl: 'http://server.test/api',
    status: status,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    totalCount: 10,
    discoveredCount: 10,
    completedCount: 2,
    failedCount: 0,
    materializedCount: 5,
    label: kind == 'artist' ? 'Artist $id' : 'Album $id',
  );
}

Widget _buildOfflineStorageSectionTestApp({
  required TargetPlatform platform,
  required Widget child,
}) {
  return MaterialApp(
    theme: ObsidianTheme.build().copyWith(platform: platform),
    home: Scaffold(body: child),
  );
}

void _noop() {}

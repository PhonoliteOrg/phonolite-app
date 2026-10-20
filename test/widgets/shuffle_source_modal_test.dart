import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/auth_state.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/inputs/local_server_toggle.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/modals/obsidian_dialog.dart';
import 'package:phonolite_app/widgets/ui/hover_row.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final layout in [
    (width: 320.0, textScale: 1.4),
    (width: 390.0, textScale: 1.0),
    (width: 1280.0, textScale: 1.0),
  ]) {
    for (final initialScope in ActionScope.values) {
      testWidgets(
        'Shuffle switches sources from $initialScope at ${layout.width}',
        (tester) async {
          final controller = (await tester.runAsync(
            () async => _Controller(initialScope),
          ))!;
          try {
            await _pump(tester, controller, layout.width, layout.textScale);
            await _open(tester);
            expect(find.text('Shuffle'), findsOneWidget);
            expect(find.text('Local Shuffle Mode'), findsNothing);
            expect(find.text('Server Shuffle Mode'), findsNothing);
            expect(
              tester
                  .widget<LocalServerToggle>(find.byType(LocalServerToggle))
                  .value,
              initialScope,
            );
            final toggle = tester.getRect(find.byType(LocalServerToggle));
            expect(toggle.center.dx, closeTo(layout.width / 2, 0.1));
            expect(
              toggle.bottom,
              lessThan(tester.getRect(find.text('Off')).top),
            );
            const labels = [
              'Off',
              'Whole Library',
              'Current Artist',
              'Current Album',
              'Current Playlist',
              'Custom',
              'Liked',
            ];
            for (final scope in [initialScope, _otherScope(initialScope)]) {
              await _switchTo(tester, scope);
              expect(_option(tester, 'Off').isActive, isTrue);
              expect(_option(tester, 'Current Artist').enabled, isTrue);
              expect(_option(tester, 'Current Album').enabled, isTrue);
              expect(controller.playbackState.shuffleMode, ShuffleMode.off);
              expect(controller.playbackState.shuffleScope, scope);
              expect(
                find
                    .descendant(
                      of: find.byType(ObsidianHoverRow),
                      matching: find.byType(Text),
                    )
                    .evaluate()
                    .map((element) => (element.widget as Text).data),
                labels,
              );
            }

            await _switchTo(tester, ActionScope.local);
            expect(_option(tester, 'Liked').enabled, isFalse);
            await _switchTo(tester, ActionScope.server);
            expect(_option(tester, 'Liked').enabled, isTrue);
            await _switchTo(tester, ActionScope.local);
            expect(_option(tester, 'Liked').enabled, isFalse);
            controller.completeLocalLikes();
            await tester.pumpAndSettle();
            expect(_option(tester, 'Liked').enabled, isTrue);
            await _choose(tester, 'Liked');
            expect(controller.selections.last, (
              mode: ShuffleMode.liked,
              scope: ActionScope.local,
            ));
            expect(controller.playbackState.serverShuffleMode, ShuffleMode.off);
            expect(find.byType(ObsidianAlertDialog), findsNothing);

            await _open(tester);
            await _switchTo(tester, ActionScope.server);
            expect(_option(tester, 'Off').isActive, isTrue);
            expect(controller.playbackState.shuffleMode, ShuffleMode.off);
            await _choose(tester, 'Whole Library');
            expect(controller.selections.last, (
              mode: ShuffleMode.all,
              scope: ActionScope.server,
            ));
            expect(
              controller.playbackState.localShuffleMode,
              ShuffleMode.liked,
            );
            await _open(tester);
            expect(
              tester
                  .widget<LocalServerToggle>(find.byType(LocalServerToggle))
                  .value,
              ActionScope.server,
            );
            await _switchTo(tester, ActionScope.local);
            expect(_option(tester, 'Liked').isActive, isTrue);
            expect(controller.playbackState.shuffleMode, ShuffleMode.liked);
            await tester.tap(find.text('CLOSE'));
            await tester.pumpAndSettle();
            expect(controller.playbackState.shuffleScope, ActionScope.local);

            await _open(tester);
            await _switchTo(tester, ActionScope.server);
            expect(_option(tester, 'Whole Library').isActive, isTrue);
            expect(controller.playbackState.shuffleMode, ShuffleMode.all);
            await _choose(tester, 'Off');
            expect(controller.playbackState.shuffleMode, ShuffleMode.off);
            expect(
              controller.playbackState.localShuffleMode,
              ShuffleMode.liked,
            );
            await _open(tester);
            expect(controller.playbackState.shuffleScope, ActionScope.server);
            expect(
              tester
                  .widget<LocalServerToggle>(find.byType(LocalServerToggle))
                  .value,
              ActionScope.server,
            );
            expect(_option(tester, 'Off').isActive, isTrue);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(controller.close);
          }
        },
      );
    }
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('current-context shuffle requires a track at $width', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () async => _Controller(ActionScope.server),
      ))!;
      controller.state = controller.state.copyWith(
        track: null,
        queueSource: PlaybackQueueSource.none,
        localPlaybackSource: LocalPlaybackSource.none,
        isLocalPlayback: false,
      );
      try {
        await _pump(tester, controller, width, 1);
        await _open(tester);
        for (final scope in [ActionScope.server, ActionScope.local]) {
          await _switchTo(tester, scope);
          expect(_option(tester, 'Off').isActive, isTrue);
          expect(_option(tester, 'Whole Library').enabled, isTrue);
          expect(_option(tester, 'Current Playlist').enabled, isFalse);
          final selectionsBeforeTap = controller.selections.length;
          for (final label in ['Current Artist', 'Current Album']) {
            expect(_option(tester, label).enabled, isFalse);
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
            expect(find.byType(ObsidianAlertDialog), findsOneWidget);
            expect(controller.selections, hasLength(selectionsBeforeTap));
            expect(controller.playbackState.shuffleMode, ShuffleMode.off);
          }
        }
        await _choose(tester, 'Whole Library');
        expect(controller.playbackState.shuffleMode, ShuffleMode.all);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });
  }

  testWidgets('disconnected Server options stay disabled while Local works', (
    tester,
  ) async {
    final controller = (await tester.runAsync(
      () async => _Controller(ActionScope.local, authorized: false),
    ))!;
    try {
      await _pump(tester, controller, 390, 1);
      await _open(tester);
      expect(_option(tester, 'Whole Library').enabled, isTrue);
      await _switchTo(tester, ActionScope.server);
      expect(_option(tester, 'Whole Library').enabled, isFalse);
      expect(_option(tester, 'Off').isActive, isTrue);
      final selectionsBeforeTap = controller.selections.length;
      await tester.tap(find.text('Whole Library'));
      await tester.pumpAndSettle();
      expect(controller.selections, hasLength(selectionsBeforeTap));
      expect(find.text('Shuffle'), findsOneWidget);
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
    }
  });
}

ActionScope _otherScope(ActionScope scope) =>
    scope == ActionScope.local ? ActionScope.server : ActionScope.local;

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(PhonoliteIcons.shuffle));
  await tester.pumpAndSettle();
}

Future<void> _switchTo(WidgetTester tester, ActionScope scope) async {
  await tester.tap(
    find.descendant(
      of: find.byType(LocalServerToggle),
      matching: find.widgetWithText(
        TextButton,
        scope == ActionScope.local ? 'LOCAL' : 'SERVER',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

ObsidianHoverRow _option(WidgetTester tester, String label) =>
    tester.widget<ObsidianHoverRow>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(ObsidianHoverRow),
          )
          .first,
    );

Future<void> _pump(
  WidgetTester tester,
  _Controller controller,
  double width,
  double textScale,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, rebuild) => NowPlayingExpandedSheet(
              state: controller.playbackState,
              useNativeMobileTreatment: width < 820,
              onOpenAlbum: null,
              onPlayPause: () {},
              onNext: () {},
              onPrev: () {},
              onStop: () {},
              onSeek: (_) {},
              onSeekPreview: (_) {},
              onShuffleChanged: (mode, {scope}) =>
                  rebuild(() => controller.select(mode, scope!)),
              onToggleRepeat: () {},
              onStreamModeChanged: (_) {},
              onVolumeChanged: (_) {},
              onToggleLike: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _track = Track(
  id: 'track',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  durationMs: 60000,
  liked: false,
  inPlaylists: false,
);

class _Controller extends AppController {
  _Controller(ActionScope scope, {this.authorized = true})
    : super(
        connection: ServerConnection(baseUrl: 'http://unused.test/api/v1'),
      ) {
    state = super.playbackState.copyWith(
      track: _track,
      shuffleScope: scope,
      isLocalPlayback: scope == ActionScope.local,
      queueSource: scope == ActionScope.local
          ? PlaybackQueueSource.offline
          : PlaybackQueueSource.liked,
      localPlaybackSource: scope == ActionScope.local
          ? LocalPlaybackSource.library
          : LocalPlaybackSource.none,
    );
  }

  final bool authorized;
  late PlaybackState state;
  final selections = <({ShuffleMode mode, ActionScope scope})>[];
  final _likes = StreamController<List<Track>>.broadcast();
  final _load = Completer<void>();
  List<Track> localLikes = [];

  @override
  PlaybackState get playbackState => state;
  @override
  AuthState get authState =>
      AuthState(isAuthorized: authorized, baseUrl: connection.baseUrl);
  @override
  List<Track> get offlineTracks => [_track];
  @override
  List<Track> get liked => [_track];
  @override
  List<Track> get localLiked => localLikes;
  @override
  Stream<List<Track>> get localLikedStream => _likes.stream;
  @override
  Future<void> loadLocalLikedTracks() => _load.future;

  void completeLocalLikes() {
    localLikes = [_track];
    _likes.add(localLikes);
    if (!_load.isCompleted) _load.complete();
  }

  void select(ShuffleMode mode, ActionScope scope) {
    selections.add((mode: mode, scope: scope));
    state = state.copyWith(shuffleMode: mode, shuffleScope: scope);
  }

  @override
  Future<void> close() async {
    if (!_load.isCompleted) _load.complete();
    await _likes.close();
    await super.close();
  }
}

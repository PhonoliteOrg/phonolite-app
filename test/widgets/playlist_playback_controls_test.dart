import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/pages/playlists/playlists_page.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/marquee_text.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_hero.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final width in [430.0, 1280.0]) {
    testWidgets(
      'server playlist download editor is prefilled at width $width',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => _PlaylistController(),
        ))!;
        controller.server = [
          controller.server.single.copyWith(
            description: 'Server playlist description',
          ),
        ];
        try {
          await _pump(
            tester,
            controller,
            const PlaylistDetailView(playlistId: 'shared-id'),
            width: width,
          );
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TechButton && widget.label == 'Download playlist',
            ),
          );
          await tester.pumpAndSettle();
          final editor = tester.widget<PlaylistEditorModal>(
            find.byType(PlaylistEditorModal),
          );
          expect(editor.title, 'Download playlist');
          expect(editor.initialValue, 'Server mix');
          expect(editor.initialDescription, 'Server playlist description');
          expect(editor.showTargetSelector, isFalse);
          expect(editor.initialTarget, PlaylistEditorTarget.local);
          final fields = find.byType(TextField);
          expect(
            tester.widget<TextField>(fields.at(0)).controller!.text,
            'Server mix',
          );
          expect(
            tester.widget<TextField>(fields.at(1)).controller!.text,
            'Server playlist description',
          );
          await tester.enterText(fields.at(0), 'My offline mix');
          await tester.enterText(fields.at(1), 'My description');
          await tester.tap(find.text('SAVE'));
          await tester.pumpAndSettle();
          expect(find.byType(PlaylistEditorModal), findsNothing);
          expect(controller.downloadedPlaylist?.id, 'shared-id');
          expect(controller.downloadedTracks, [_track]);
          expect(controller.downloadName, 'My offline mix');
          expect(controller.downloadDescription, 'My description');
          expect(
            controller.downloadImageEdit?.kind,
            PlaylistImageEditKind.keep,
          );
          expect(controller.server.single.name, 'Server mix');
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
    );
  }

  testWidgets(
    'download playlist waits for tracks and is absent on local copies',
    (tester) async {
      final controller = (await tester.runAsync(
        () async => _PlaylistController(),
      ))!;
      controller.trackLoad = Completer<void>();
      try {
        await _pump(
          tester,
          controller,
          const PlaylistDetailView(playlistId: 'shared-id'),
        );
        final button = find.byWidgetPredicate(
          (widget) =>
              widget is TechButton && widget.label == 'Download playlist',
        );
        expect(tester.widget<TechButton>(button).onTap, isNull);
        controller.trackLoad!.complete();
        await _pumpUpdates(tester);
        expect(tester.widget<TechButton>(button).onTap, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(
          tester,
          controller,
          const PlaylistDetailView(playlistId: 'shared-id', isLocal: true),
        );
        expect(find.byTooltip('Download playlist'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    },
  );

  for (final width in [430.0, 1280.0]) {
    testWidgets(
      'playlist grid geometry stays fixed during selection at width $width',
      (tester) async {
        final controller = (await tester.runAsync(
          () async => _PlaylistController(),
        ))!;
        try {
          await _pump(tester, controller, const PlaylistsPage(), width: width);

          Finder cardFor(String title) => find.ancestor(
            of: find.text(title),
            matching: find.byType(AlbumCard),
          );
          List<Rect> geometry() => [
            for (final title in ['Local mix', 'Server mix']) ...[
              tester.getRect(cardFor(title)),
              tester.getRect(
                find.descendant(
                  of: cardFor(title),
                  matching: find.byType(AlbumArt),
                ),
              ),
              tester.getRect(find.text(title)),
            ],
          ];

          final normalGeometry = geometry();
          expect(find.byIcon(PhonoliteIcons.play), findsNothing);

          await tester.tap(find.byTooltip('Edit playlists'));
          await _pumpUpdates(tester);
          expect(geometry(), normalGeometry);
          expect(find.byIcon(PhonoliteIcons.play), findsNothing);

          await tester.tap(cardFor('Local mix'));
          await _pumpUpdates(tester);
          expect(
            tester.widget<AlbumCard>(cardFor('Local mix')).selected,
            isTrue,
          );
          expect(geometry(), normalGeometry);

          await tester.tap(cardFor('Local mix'));
          await _pumpUpdates(tester);
          expect(
            tester.widget<AlbumCard>(cardFor('Local mix')).selected,
            isFalse,
          );
          expect(geometry(), normalGeometry);

          await tester.tap(find.byTooltip('Cancel'));
          await _pumpUpdates(tester);
          expect(geometry(), normalGeometry);
          expect(find.byIcon(PhonoliteIcons.play), findsNothing);

          await tester.tap(find.text('Local mix'));
          await tester.pumpAndSettle();
          expect(find.byType(PlaylistDetailView), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, controller);
        }
      },
    );
  }

  for (final isLocal in [true, false]) {
    for (final surface in ['grid', 'list', 'detail']) {
      for (final width in [430.0, 1280.0]) {
        testWidgets(
          '${isLocal ? 'local' : 'server'} $surface opens banner playback at width $width',
          (tester) async {
            final controller = (await tester.runAsync(
              () async => _PlaylistController(listMode: surface == 'list'),
            ))!;
            try {
              await _pump(
                tester,
                controller,
                surface == 'detail'
                    ? PlaylistDetailView(
                        playlistId: 'shared-id',
                        isLocal: isLocal,
                      )
                    : const PlaylistsPage(),
                width: width,
              );
              if (surface != 'detail') {
                expect(find.byIcon(PhonoliteIcons.play), findsNothing);
                expect(find.byIcon(PhonoliteIcons.square), findsNothing);
                controller.activate(isLocal: !isLocal);
                await _pumpUpdates(tester);
                expect(find.byIcon(PhonoliteIcons.play), findsNothing);
                expect(find.byIcon(PhonoliteIcons.square), findsNothing);

                await tester.tap(
                  find.text(isLocal ? 'Local mix' : 'Server mix'),
                );
                await _pumpUpdates(tester);
                await _pumpUpdates(tester);
              }
              final banner = find.byType(AlbumHero);
              final playButton = find.descendant(
                of: banner,
                matching: find.byType(ObsidianHudIconButton),
              );
              expect(playButton, findsOneWidget);
              expect(
                tester.getSize(playButton).height,
                greaterThanOrEqualTo(48),
              );
              final bannerRect = tester.getRect(banner);
              final buttonRect = tester.getRect(playButton);
              expect(bannerRect.contains(buttonRect.topLeft), isTrue);
              expect(bannerRect.contains(buttonRect.bottomRight), isTrue);
              expect(buttonRect.top - bannerRect.top, lessThanOrEqualTo(24));
              expect(
                bannerRect.right - buttonRect.right,
                lessThanOrEqualTo(24),
              );
              expect(find.byTooltip('Play playlist'), findsOneWidget);
              expect(find.byIcon(PhonoliteIcons.play), findsOneWidget);

              // Local and server playlists deliberately have the same ID.
              controller.activate(isLocal: !isLocal);
              await _pumpUpdates(tester);
              expect(find.byIcon(PhonoliteIcons.play), findsOneWidget);
              expect(find.byIcon(PhonoliteIcons.square), findsNothing);

              await tester.tap(playButton);
              await _pumpUpdates(tester);
              expect(controller.playedLocally, isLocal);
              expect(controller.playedPlaylistId, 'shared-id');
              expect(controller.playCalls, 1);
              expect(find.byTooltip('Play playlist'), findsOneWidget);
              expect(find.byTooltip('Stop playlist'), findsNothing);
              expect(find.byIcon(PhonoliteIcons.square), findsNothing);
              expect(find.byIcon(PhonoliteIcons.play), findsOneWidget);
              expect(tester.getRect(playButton), buttonRect);

              controller.emit(
                controller.playbackState.copyWith(
                  position: const Duration(seconds: 30),
                ),
              );
              await _pumpUpdates(tester);
              await tester.tap(playButton);
              await _pumpUpdates(tester);
              expect(controller.playCalls, 2);
              expect(controller.stopCalls, 0);
              expect(controller.playbackState.position, Duration.zero);
              expect(controller.playbackState.isPlaying, isTrue);
              expect(find.byIcon(PhonoliteIcons.square), findsNothing);
              expect(find.byIcon(PhonoliteIcons.play), findsOneWidget);

              controller.emit(
                controller.playbackState.copyWith(
                  isPlaying: false,
                  position: const Duration(seconds: 20),
                ),
              );
              await _pumpUpdates(tester);
              await tester.tap(playButton);
              await _pumpUpdates(tester);
              expect(controller.playCalls, 3);
              expect(controller.playedLocally, isLocal);
              expect(controller.stopCalls, 0);
              expect(controller.playbackState.position, Duration.zero);
              expect(controller.playbackState.isPlaying, isTrue);
              expect(find.byTooltip('Play playlist'), findsOneWidget);
              expect(find.byIcon(PhonoliteIcons.square), findsNothing);
              expect(find.byIcon(PhonoliteIcons.play), findsOneWidget);
              expect(tester.getRect(playButton), buttonRect);
              expect(tester.takeException(), isNull);
            } finally {
              await _dispose(tester, controller);
            }
          },
        );
      }
    }
  }

  testWidgets(
    'expanded player keeps touch controls reachable on a small phone',
    (tester) async {
      final controller = (await tester.runAsync(
        () async => _PlaylistController(),
      ))!..activate(isLocal: true);
      var previousCalls = 0;
      try {
        await _pump(
          tester,
          controller,
          NowPlayingExpandedSheet(
            state: controller.playbackState,
            onOpenAlbum: null,
            onPlayPause: () {},
            onNext: () {},
            onPrev: () => previousCalls++,
            onStop: () {},
            onSeek: (_) {},
            onSeekPreview: (_) {},
            onShuffleChanged: (_, {scope}) {},
            onToggleRepeat: () {},
            onStreamModeChanged: (_) {},
            onVolumeChanged: (_) {},
            onToggleLike: () {},
          ),
          width: 320,
          height: 640,
        );
        for (final element in find.byType(ObsidianHudIconButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(640));
        }
        final previous = find.byWidgetPredicate(
          (widget) =>
              widget is ObsidianHudIconButton &&
              widget.icon == PhonoliteIcons.skipBack,
        );
        await tester.tapAt(
          tester.getRect(previous).bottomRight - const Offset(2, 2),
        );
        await tester.pump();
        expect(previousCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('mobile player artwork and tags fit without scrolling at $size', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () async => _PlaylistController(),
      ))!..activate(isLocal: false);
      try {
        await _pump(
          tester,
          controller,
          NowPlayingExpandedSheet(
            useNativeMobileTreatment: true,
            onOpenAlbum: null,
            state: controller.playbackState.copyWith(
              shuffleMode: ShuffleMode.custom,
              repeatMode: PlaybackRepeatMode.one,
              streamRttMs: 28,
              bufferRatio: 0.5,
            ),
            onPlayPause: () {},
            onNext: () {},
            onPrev: () {},
            onStop: () {},
            onSeek: (_) {},
            onSeekPreview: (_) {},
            onShuffleChanged: (_, {scope}) {},
            onToggleRepeat: () {},
            onStreamModeChanged: (_) {},
            onVolumeChanged: (_) {},
            onToggleLike: () {},
          ),
          width: size.width,
          height: size.height,
        );

        final verticalScroll = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        );
        expect(verticalScroll, findsNothing);
        expect(find.text('SERVER'), findsOneWidget);
        expect(find.text('LOOP'), findsOneWidget);
        Rect controlRect(IconData icon) => tester.getRect(
          find.byWidgetPredicate(
            (widget) => widget is ObsidianHudIconButton && widget.icon == icon,
          ),
        );
        final previous = controlRect(PhonoliteIcons.skipBack);
        final next = controlRect(PhonoliteIcons.skipForward);
        final shuffle = controlRect(PhonoliteIcons.shuffle);
        final stop = controlRect(PhonoliteIcons.square);
        final repeat = controlRect(PhonoliteIcons.repeat);
        expect(previous.center.dy, next.center.dy);
        expect(repeat.center.dy, previous.center.dy);
        expect(stop.center.dy, repeat.center.dy);
        expect(shuffle.top, greaterThan(previous.bottom));
        final device = controlRect(PhonoliteIcons.speaker);
        expect(shuffle.center.dy, device.center.dy);
        final quality = tester.getRect(
          find
              .ancestor(
                of: find.text('HQ'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(quality.width, lessThan(60));
        expect(quality.height, lessThanOrEqualTo(36));
        expect(quality.left, greaterThanOrEqualTo(device.right));
        expect(
          quality.center.dy,
          device.center.dy,
          reason:
              'The compact quality button should sit beside the audio device button',
        );
        final horizontalScroll = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        );
        expect(
          horizontalScroll,
          findsNothing,
          reason: 'Tags should wrap rather than require horizontal scrolling',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    });
  }

  for (final isLocal in [true, false]) {
    for (final surface in ['desktop', 'mini', 'expanded']) {
      testWidgets(
        '${isLocal ? 'local' : 'server'} $surface player shows and updates the playlist name',
        (tester) async {
          final controller = (await tester.runAsync(
            () async => _PlaylistController(),
          ))!..activate(isLocal: isLocal);
          final state = controller.playbackState;
          final Widget player;
          if (surface == 'mini') {
            player = NowPlayingMiniBar(
              state: state,
              onPlayPause: () {},
              onNext: () {},
              onExpand: () {},
            );
          } else if (surface == 'expanded') {
            player = NowPlayingExpandedSheet(
              state: state,
              onOpenAlbum: null,
              onPlayPause: () {},
              onNext: () {},
              onPrev: () {},
              onStop: () {},
              onSeek: (_) {},
              onSeekPreview: (_) {},
              onShuffleChanged: (_, {scope}) {},
              onToggleRepeat: () {},
              onStreamModeChanged: (_) {},
              onVolumeChanged: (_) {},
              onToggleLike: () {},
            );
          } else {
            player = NowPlayingBar(
              state: state,
              onOpenAlbum: null,
              onPlayPause: () {},
              onNext: () {},
              onPrev: () {},
              onStop: () {},
              onSeek: (_) {},
              onSeekPreview: (_) {},
              onShuffleChanged: (_, {scope}) {},
              onToggleRepeat: () {},
              onStreamModeChanged: (_) {},
              onVolumeChanged: (_) {},
              onToggleLike: () {},
            );
          }
          await _pump(
            tester,
            controller,
            player,
            width: surface == 'desktop' ? 1280 : 430,
          );
          final playlistName = isLocal ? 'Local mix' : 'Server mix';
          expect(find.text(playlistName), findsOneWidget);
          expect(find.text('SOURCE: LOCAL PLAYLIST'), findsNothing);
          expect(find.text('SOURCE: PLAYLIST'), findsNothing);
          expect(
            find.textContaining('KBPS'),
            isLocal ? findsNothing : findsOneWidget,
          );
          expect(find.text(isLocal ? 'LOCAL' : 'SERVER'), findsOneWidget);
          expect(find.text(isLocal ? 'SERVER' : 'LOCAL'), findsNothing);
          expect(find.text('IDLE'), findsNothing);
          expect(find.byIcon(Icons.pause), findsOneWidget);
          expect(find.byIcon(PhonoliteIcons.pause), findsNothing);
          expect(
            tester.widget<Text>(find.text(playlistName)).style?.color,
            isNull,
          );

          // A rename updates the tag even while the track stays unchanged.
          const renamed = '12345678901234567890123456789012';
          controller.emitPlaylistRename(renamed, isLocal: isLocal);
          await _pumpUpdates(tester);
          expect(find.text(renamed), findsOneWidget);
          expect(find.text(playlistName), findsNothing);
          expect(tester.takeException(), isNull);
          await _dispose(tester, controller);
        },
      );
    }
  }
  for (final surface in ['desktop', 'mini', 'expanded']) {
    testWidgets('$surface player scrolls artist-album text at half title speed', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () async => _PlaylistController(),
      ))!..activate(isLocal: false);
      final track = _track.copyWith(
        title:
            'A very long track title with an extended live recording description '
            'and many featured collaborators from the special anniversary edition '
            'recorded at a concert with an even longer venue name',
        artist: 'An artist with a very long name and several collaborators',
        album: 'An album with a very long title and a special edition subtitle',
      );
      final state = controller.playbackState.copyWith(track: track);
      try {
        await _pump(
          tester,
          controller,
          _marqueePlayer(state, surface),
          width: surface == 'desktop' ? 1280 : 390,
        );
        final title = find.byWidgetPredicate(
          (widget) => widget is MarqueeText && widget.text == track.title,
        );
        final subtitle = find.byWidgetPredicate(
          (widget) =>
              widget is MarqueeText &&
              widget.text == '${track.artist} - ${track.album}',
        );
        final scroll = find.descendant(
          of: subtitle,
          matching: find.byType(Scrollable),
        );
        expect(title, findsOneWidget);
        expect(subtitle, findsOneWidget);
        expect(scroll, findsOneWidget);
        final titleScroll = find.descendant(
          of: title,
          matching: find.byType(Scrollable),
        );
        expect(titleScroll, findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        final titlePosition = tester
            .state<ScrollableState>(titleScroll)
            .position;
        final subtitlePosition = tester.state<ScrollableState>(scroll).position;
        final titleStart = titlePosition.pixels;
        final subtitleStart = subtitlePosition.pixels;
        await tester.pump(const Duration(milliseconds: 500));
        final titleDistance = titlePosition.pixels - titleStart;
        final subtitleDistance = subtitlePosition.pixels - subtitleStart;
        expect(titleDistance, greaterThan(0));
        expect(subtitleDistance, closeTo(titleDistance * 0.5, 0.05));
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, controller);
      }
    });
  }
}

Widget _marqueePlayer(PlaybackState state, String surface) {
  if (surface == 'mini') {
    return NowPlayingMiniBar(
      state: state,
      onPlayPause: () {},
      onNext: () {},
      onExpand: () {},
    );
  }
  if (surface == 'expanded') {
    return NowPlayingExpandedSheet(
      state: state,
      onOpenAlbum: null,
      onPlayPause: () {},
      onNext: () {},
      onPrev: () {},
      onStop: () {},
      onSeek: (_) {},
      onSeekPreview: (_) {},
      onShuffleChanged: (_, {scope}) {},
      onToggleRepeat: () {},
      onStreamModeChanged: (_) {},
      onVolumeChanged: (_) {},
      onToggleLike: () {},
    );
  }
  return NowPlayingBar(
    state: state,
    onOpenAlbum: null,
    onPlayPause: () {},
    onNext: () {},
    onPrev: () {},
    onStop: () {},
    onSeek: (_) {},
    onSeekPreview: (_) {},
    onShuffleChanged: (_, {scope}) {},
    onToggleRepeat: () {},
    onStreamModeChanged: (_) {},
    onVolumeChanged: (_) {},
    onToggleLike: () {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  _PlaylistController controller,
  Widget child, {
  double width = 1280,
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    AppScope(controller: controller, child: wrapInTestApp(child)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _dispose(
  WidgetTester tester,
  _PlaylistController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await controller.playbackUpdates.close();
    await controller.playlistUpdates.close();
    await controller.serverPlaylistUpdates.close();
    await controller.close();
  });
}

Future<void> _pumpUpdates(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

final _track = Track(
  id: 'track',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  durationMs: 60000,
  liked: false,
  inPlaylists: true,
);

class _PlaylistController extends AppController {
  _PlaylistController({this.listMode = false})
    : super(
        connection: ServerConnection(baseUrl: 'http://server.test/api'),
      ) {
    currentPlayback = super.playbackState;
  }

  final bool listMode;
  late PlaybackState currentPlayback;
  final playbackUpdates = StreamController<PlaybackState>.broadcast();
  final playlistUpdates = StreamController<List<Playlist>>.broadcast();
  final serverPlaylistUpdates = StreamController<List<Playlist>>.broadcast();
  List<Playlist> local = [
    Playlist(id: 'shared-id', name: 'Local mix', trackIds: ['track']),
  ];
  List<Playlist> server = [
    Playlist(id: 'shared-id', name: 'Server mix', trackIds: ['track']),
  ];
  int stopCalls = 0;
  int playCalls = 0;
  bool? playedLocally;
  String? playedPlaylistId;
  Completer<void>? trackLoad;
  Playlist? downloadedPlaylist;
  List<Track>? downloadedTracks;
  String? downloadName;
  String? downloadDescription;
  PlaylistImageEdit? downloadImageEdit;

  void emit(PlaybackState state) {
    currentPlayback = state;
    playbackUpdates.add(state);
  }

  void activate({required bool isLocal}) {
    emit(
      currentPlayback.copyWith(
        track: _track,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 1),
        bitrateKbps: 320,
        queueSource: isLocal
            ? PlaybackQueueSource.offline
            : PlaybackQueueSource.playlist,
        queueSourcePlaylistId: 'shared-id',
        localPlaybackSource: isLocal
            ? LocalPlaybackSource.playlist
            : LocalPlaybackSource.none,
        isLocalPlayback: isLocal,
      ),
    );
  }

  void emitPlaylistRename(String name, {required bool isLocal}) {
    if (isLocal) {
      local = [local.single.copyWith(name: name)];
      playlistUpdates.add(local);
    } else {
      server = [server.single.copyWith(name: name)];
      serverPlaylistUpdates.add(server);
    }
  }

  @override
  PlaybackState get playbackState => currentPlayback;
  @override
  Stream<PlaybackState> get playbackStream => playbackUpdates.stream;
  @override
  AuthState get authState =>
      AuthState(isAuthorized: true, baseUrl: connection.baseUrl);
  @override
  bool get collectionListMode => listMode;
  @override
  List<Playlist> get localPlaylists => local;
  @override
  Stream<List<Playlist>> get localPlaylistsStream => playlistUpdates.stream;
  @override
  List<Playlist> get playlists => server;
  @override
  Stream<List<Playlist>> get playlistsStream => serverPlaylistUpdates.stream;
  @override
  List<Track> get localPlaylistTracks => [_track];
  @override
  List<Track> get playlistTracks => [_track];
  @override
  Future<void> loadLocalPlaylists() async {}
  @override
  Future<void> loadPlaylists() async {}
  @override
  Future<void> loadLocalPlaylistTracks(String playlistId) async {}
  @override
  Future<void> loadPlaylistTracks(String playlistId) async {
    await trackLoad?.future;
  }

  @override
  Future<void> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    downloadedPlaylist = playlist;
    downloadedTracks = tracks;
    downloadName = name;
    downloadDescription = description;
    downloadImageEdit = imageEdit;
  }

  @override
  Future<void> playLocalPlaylistFromTop(String playlistId) async {
    playCalls++;
    playedPlaylistId = playlistId;
    playedLocally = true;
    activate(isLocal: true);
  }

  @override
  Future<void> playPlaylistFromTop(String playlistId) async {
    playCalls++;
    playedPlaylistId = playlistId;
    playedLocally = false;
    activate(isLocal: false);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    emit(
      currentPlayback.copyWith(
        track: null,
        isPlaying: false,
        queueSource: PlaybackQueueSource.none,
        queueSourcePlaylistId: null,
        localPlaybackSource: LocalPlaybackSource.none,
        isLocalPlayback: false,
      ),
    );
  }
}

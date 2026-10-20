import 'package:flutter/material.dart';

import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';
import 'package:phonolite_app/widgets/ui/playlist_add_icon.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/widgets/display/album_art.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/navigation/adaptive_scaffold.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final playback in const ['server', 'local', 'idle']) {
    testWidgets(
      '$playback desktop player scales artwork, metadata and both control groups together',
      (tester) async {
        final probe = (await tester.runAsync(
          () async => _PlayerProbe(playback),
        ))!;
        _configureView(tester);
        try {
          await _pumpScaffold(tester, probe, width: 1280);
          final baseline = _playerMeasurements(tester, playback);
          var previousArtWidth = baseline['artwork']!.width;

          for (final width in const [1120.0, 1040.0, 1000.0, 980.0]) {
            await _pumpScaffold(tester, probe, width: width);
            expect(find.byType(NowPlayingBar), findsOneWidget);
            expect(find.byType(NowPlayingMiniBar), findsNothing);

            final resized = _playerMeasurements(tester, playback);
            final art = resized['artwork']!;
            final ratio = art.width / baseline['artwork']!.width;
            expect(art.width, lessThan(previousArtWidth));
            expect(art.width, closeTo(art.height, 0.001));

            for (final item in baseline.entries) {
              final actual = resized[item.key]!;
              expect(
                actual.width,
                closeTo(item.value.width * ratio, 0.01),
                reason: '${item.key} width at ${width}px',
              );
              expect(
                actual.height,
                closeTo(item.value.height * ratio, 0.01),
                reason: '${item.key} height at ${width}px',
              );
              expect(actual.left, greaterThanOrEqualTo(0));
              expect(actual.right, lessThanOrEqualTo(width));
            }
            previousArtWidth = art.width;
            expect(tester.takeException(), isNull);
          }

          // The three desktop groups stay visible until the actual scaffold's
          // mobile breakpoint, where its compact player takes over.
          await _pumpScaffold(tester, probe, width: 979);
          expect(find.byType(NowPlayingBar), findsNothing);
          expect(find.byType(NowPlayingMiniBar), findsOneWidget);
          if (playback == 'local') {
            expect(find.text('LOCAL'), findsOneWidget);
            expect(find.text('SERVER'), findsNothing);
            expect(find.text('IDLE'), findsNothing);
          } else if (playback == 'server') {
            expect(find.text('SERVER'), findsOneWidget);
            expect(find.text('LOCAL'), findsNothing);
          } else {
            expect(find.text('LOCAL'), findsNothing);
            expect(find.text('SERVER'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await probe.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('scaled desktop controls retain their rendered hit targets', (
    tester,
  ) async {
    final probe = (await tester.runAsync(() async => _PlayerProbe('server')))!;
    _configureView(tester);
    try {
      await _pumpScaffold(tester, probe, width: 980);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(PhonoliteIcons.skipForward));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(PhonoliteIcons.heart));
      await tester.pump(const Duration(milliseconds: 250));

      expect(probe.playTaps, 1);
      expect(probe.nextTaps, 1);
      expect(probe.likeTaps, 1);

      final volume = _renderedRect(tester, _volumeSlider());
      await tester.tapAt(
        Offset(volume.left + volume.width * 0.8, volume.center.dy),
      );
      await tester.pump();
      expect(probe.lastVolume, isNotNull);
      expect(probe.lastVolume!, greaterThan(0.5));
      expect(tester.takeException(), isNull);
    } finally {
      await probe.dispose(tester);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final layout in [
    (size: const Size(320, 568), textScale: 1.0),
    (size: const Size(390, 700), textScale: 1.0),
    (size: const Size(430, 932), textScale: 1.0),
    (size: const Size(320, 568), textScale: 1.4),
    (size: const Size(390, 844), textScale: 1.4),
  ]) {
    for (final playback in ['local', 'server']) {
      testWidgets(
        '$playback mobile tray fits without scrolling at ${layout.size}, text scale ${layout.textScale}',
        (tester) async {
          final probe = (await tester.runAsync(
            () async => _PlayerProbe(playback),
          ))!;
          _configureView(tester);
          tester.view.physicalSize = layout.size;
          Duration? seekPosition;
          try {
            await tester.pumpWidget(
              AppScope(
                controller: probe.controller,
                child: wrapInTestApp(
                  Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        padding: const EdgeInsets.only(top: 44, bottom: 34),
                        viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
                        textScaler: TextScaler.linear(layout.textScale),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: NowPlayingExpandedSheet(
                          state: probe.state,
                          useNativeMobileTreatment: true,
                          onOpenAlbum: null,
                          onPlayPause: () => probe.playTaps++,
                          onNext: () => probe.nextTaps++,
                          onPrev: () => probe.prevTaps++,
                          onStop: () => probe.stopTaps++,
                          onSeek: (position) => seekPosition = position,
                          onSeekPreview: (_) {},
                          onShuffleChanged: (_, {scope}) {},
                          onToggleRepeat: () => probe.repeatTaps++,
                          onStreamModeChanged: (_) {},
                          onVolumeChanged: (volume) =>
                              probe.lastVolume = volume,
                          onToggleLike: _noop,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final sheet = find.byType(NowPlayingExpandedSheet);
            final seek = find.byWidgetPredicate(
              (widget) => widget is Slider && widget.max > 1,
            );
            final seekRect = tester.getRect(seek);
            final art = find.byType(AlbumArt);
            final artRect = tester.getRect(art);
            final titleRect = tester.getRect(find.text('Song'));
            final subtitleRect = tester.getRect(find.text('Artist - Album'));
            expect(find.byType(Slider), findsOneWidget);
            expect(find.byIcon(PhonoliteIcons.volume2), findsNothing);
            expect(
              tester
                  .widgetList<SingleChildScrollView>(
                    find.descendant(
                      of: sheet,
                      matching: find.byType(SingleChildScrollView),
                    ),
                  )
                  .where((scroll) => scroll.scrollDirection == Axis.vertical),
              isEmpty,
            );
            expect(artRect.width, greaterThan(0));
            expect(artRect.left, greaterThanOrEqualTo(16));
            expect(artRect.right, lessThanOrEqualTo(layout.size.width - 16));
            expect(artRect.width, closeTo(artRect.height, 0.01));
            expect(artRect.top, greaterThanOrEqualTo(44 + 30 + 12));
            expect(
              artRect.bottom + 22,
              lessThanOrEqualTo(titleRect.top + 0.01),
            );
            expect(subtitleRect.bottom, lessThan(seekRect.top));
            expect(seekRect.width, closeTo(layout.size.width - 24, 0.01));
            expect(seekRect.height, greaterThanOrEqualTo(48));

            final controls = [
              PhonoliteIcons.skipBack,
              PhonoliteIcons.repeat,
              Icons.play_arrow,
              PhonoliteIcons.square,
              PhonoliteIcons.skipForward,
            ].map((icon) => tester.getRect(find.byIcon(icon))).toList();
            expect(controls[2].center.dx, closeTo(layout.size.width / 2, 0.01));
            for (final rect in controls) {
              expect(rect.center.dy, closeTo(controls.first.center.dy, 0.01));
              expect(rect.left, greaterThanOrEqualTo(12));
              expect(rect.right, lessThanOrEqualTo(layout.size.width - 12));
              expect(rect.bottom, lessThanOrEqualTo(layout.size.height - 34));
            }
            for (var index = 1; index < controls.length; index++) {
              expect(
                controls[index].left,
                greaterThan(controls[index - 1].right),
              );
            }
            final shuffle = tester.getRect(find.byIcon(PhonoliteIcons.shuffle));
            final device = tester.getRect(find.byIcon(PhonoliteIcons.speaker));
            expect(shuffle.top, greaterThan(controls.first.bottom));
            expect(shuffle.center.dy, closeTo(device.center.dy, 0.01));
            await tester.drag(art, const Offset(0, -80));
            await tester.pumpAndSettle();
            expect(tester.getRect(art), artRect);

            await tester.tapAt(
              Offset(seekRect.left + seekRect.width * 0.75, seekRect.center.dy),
            );
            await tester.pump();
            expect(seekPosition?.inSeconds, inInclusiveRange(40, 50));
            await tester.tap(find.byIcon(Icons.play_arrow));
            await tester.tap(find.byIcon(PhonoliteIcons.square));
            await tester.tap(find.byIcon(PhonoliteIcons.skipBack));
            await tester.tap(find.byIcon(PhonoliteIcons.skipForward));
            await tester.tap(find.byIcon(PhonoliteIcons.repeat));
            expect([
              probe.playTaps,
              probe.stopTaps,
              probe.prevTaps,
              probe.nextTaps,
              probe.repeatTaps,
            ], everyElement(1));
            expect(tester.takeException(), isNull);
          } finally {
            await probe.dispose(tester);
          }
        },
      );
    }
  }
}

void _configureView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpScaffold(
  WidgetTester tester,
  _PlayerProbe probe, {
  required double width,
}) async {
  final size = Size(width, 800);
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    AppScope(
      controller: probe.controller,
      child: MaterialApp(
        theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.windows),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: ObsidianScale(
            scale: ObsidianScale.compute(width),
            child: AdaptiveScaffold(
              destinations: const [
                NavigationDestination(
                  icon: Icon(PhonoliteIcons.disc3),
                  label: 'Library',
                ),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              page: const SizedBox.expand(),
              playbackState: probe.state,
              onOpenAlbum: _noop,
              onPlayPause: () => probe.playTaps++,
              onNext: () => probe.nextTaps++,
              onPrev: _noop,
              onStop: _noop,
              onSeek: (_) {},
              onSeekPreview: (_) {},
              onShuffleChanged: (_, {scope}) {},
              onToggleRepeat: _noop,
              onStreamModeChanged: (_) {},
              onVolumeChanged: (value) => probe.lastVolume = value,
              onToggleLike: () => probe.likeTaps++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, Rect> _playerMeasurements(WidgetTester tester, String playback) {
  final idle = playback == 'idle';
  final local = playback == 'local';
  final measurements = <String, Finder>{
    'artwork': find.byType(AlbumArt),
    'title': find.text(idle ? 'NO TRACK PLAYING' : 'Song'),
    'subtitle': find.text(idle ? 'IDLE' : 'Artist - Album').first,
    'info tag': find
        .text(
          idle
              ? 'IDLE'
              : local
              ? 'LOCAL'
              : '320 KBPS',
        )
        .last,
    'play icon': find.byIcon(Icons.play_arrow),
    'next icon': find.byIcon(PhonoliteIcons.skipForward),
    'playlist icon': find.byType(PlaylistAddIcon),
    'like icon': find.byIcon(PhonoliteIcons.heart),
    'device icon': find.byIcon(PhonoliteIcons.speaker),
    'volume icon': find.byIcon(PhonoliteIcons.volume2),
    'volume slider': _volumeSlider(),
  };
  if (playback == 'server') {
    measurements['location tag'] = find.text('SERVER');
    expect(find.text('LOCAL'), findsNothing);
    measurements['source tag'] = find.text('LIKED TRACKS');
    measurements['quality text'] = find.text('AUTO');
    measurements['quality button'] = find
        .ancestor(
          of: find.text('AUTO'),
          matching: find.byType(AnimatedContainer),
        )
        .first;
  } else {
    expect(find.text('AUTO'), findsNothing);
  }
  if (local) {
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('SERVER'), findsNothing);
    expect(find.text('IDLE'), findsNothing);
  } else if (idle) {
    expect(find.text('LOCAL'), findsNothing);
    expect(find.text('SERVER'), findsNothing);
  }
  return {
    for (final item in measurements.entries)
      item.key: _renderedRect(tester, item.value),
  };
}

Finder _volumeSlider() {
  final volumeRow = find
      .ancestor(
        of: find.byIcon(PhonoliteIcons.volume2),
        matching: find.byType(Row),
      )
      .first;
  return find.descendant(of: volumeRow, matching: find.byType(Slider));
}

Rect _renderedRect(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final box = tester.renderObject<RenderBox>(finder);
  // getSize reports layout dimensions before ancestor transforms. Measure
  // the visible rectangle instead, including the fitted player's scale.
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

class _PlayerProbe {
  _PlayerProbe(String playback) {
    state = controller.playbackState.copyWith(
      track: playback == 'idle'
          ? null
          : Track(
              id: 'song',
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 60000,
              liked: false,
              inPlaylists: false,
            ),
      duration: const Duration(minutes: 1),
      volume: 0.5,
      streamMode: StreamMode.auto,
      bitrateKbps: playback == 'server' ? 320 : null,
      streamRttMs: playback == 'server' ? 28 : null,
      queueSource: playback == 'local'
          ? PlaybackQueueSource.offline
          : playback == 'server'
          ? PlaybackQueueSource.liked
          : PlaybackQueueSource.none,
      localPlaybackSource: playback == 'local'
          ? LocalPlaybackSource.library
          : LocalPlaybackSource.none,
      isLocalPlayback: playback == 'local',
    );
  }

  final controller = AppController(
    connection: ServerConnection(baseUrl: 'http://server.test/api/v1'),
  );
  late final PlaybackState state;
  int playTaps = 0;
  int nextTaps = 0;
  int prevTaps = 0;
  int stopTaps = 0;
  int repeatTaps = 0;
  int likeTaps = 0;
  double? lastVolume;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(controller.close);
  }
}

void _noop() {}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/compact_playback_footer.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_output_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_progress_bar.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_track_details.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_transport_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shell/adaptive_scaffold.dart';
import 'package:phonolite_app/ui/shell/navigation/app_bottom_navigation.dart';
import 'package:phonolite_app/ui/shell/navigation/app_side_navigation.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);
  final desktopPlatforms = TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux});

  for (final playback in const ['server', 'local', 'idle']) {
    testWidgets('$playback desktop player scales artwork, metadata and both control groups together', (tester) async {
      final probe = (await tester.runAsync(() async => _PlayerProbe(playback)))!;
      _configureView(tester);
      try {
        await _pumpScaffold(tester, probe, width: 1280);
        final baseline = _playerMeasurements(tester, playback);
        var previousArtWidth = baseline['artwork']!.width;

        for (final width in const [1120.0, 1040.0, 1000.0, 980.0, 979.0, 900.0, 768.0, 640.0, 630.0, 600.0]) {
          await _pumpScaffold(tester, probe, width: width);
          expect(find.byType(NowPlayingBar), findsOneWidget);
          expect(find.byType(NowPlayingMiniBar), findsNothing);

          final resized = _playerMeasurements(tester, playback);
          final art = resized['artwork']!;
          final ratio = art.width / baseline['artwork']!.width;
          expect(art.width, lessThanOrEqualTo(previousArtWidth + 0.01));
          expect(art.width, closeTo(art.height, 0.001));

          for (final item in baseline.entries) {
            final actual = resized[item.key]!;
            expect(actual.width, closeTo(item.value.width * ratio, 0.01), reason: '${item.key} width at ${width}px');
            expect(actual.height, closeTo(item.value.height * ratio, 0.01), reason: '${item.key} height at ${width}px');
            expect(actual.left, greaterThanOrEqualTo(0));
            expect(actual.right, lessThanOrEqualTo(width));
          }

          _expectDesktopLayout(tester);
          previousArtWidth = art.width;
          expect(tester.takeException(), isNull);
        }
        expect(previousArtWidth, lessThan(baseline['artwork']!.width));

        // Windows smaller than the native minimum still have a compact
        // fallback, for example when embedded or constrained by the OS.
        await _pumpScaffold(tester, probe, width: 599);
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
    }, variant: desktopPlatforms);

    testWidgets('$playback tiled desktop retains navigation and clears the player at narrow widths', (tester) async {
      final probe = (await tester.runAsync(() async => _PlayerProbe(playback)))!;
      _configureView(tester);
      try {
        for (final width in const [600.0, 640.0, 683.0, 768.0, 900.0, 923.0, 924.0, 925.0, 960.0, 979.0, 980.0]) {
          await _pumpScaffold(tester, probe, width: width, height: 360);
          expect(find.byType(AppSideNavigation), findsOneWidget);
          expect(find.byType(AppBottomNavigation), findsNothing);
          expect(find.byType(NowPlayingBar), findsOneWidget);
          expect(find.byType(NowPlayingMiniBar), findsNothing);

          final player = tester.getRect(find.byType(NowPlayingBar));
          final inset = tester.widget<PlaybackContentInset>(find.byType(PlaybackContentInset));
          expect(inset.bottom, closeTo(player.height, 0.01), reason: 'scroll clearance at ${width}px');
          expect(player.left, greaterThanOrEqualTo(0));
          expect(player.right, lessThanOrEqualTo(width));
          expect(player.bottom, closeTo(360, 0.01));
          expect(player.top, greaterThan(0));
          expect(player.height, lessThan(360 / 2));
          _expectDesktopLayout(tester);
          expect(tester.takeException(), isNull, reason: 'layout at $width x 360');
        }

        await _pumpScaffold(tester, probe, width: 600, height: 360);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byIcon(PhonoliteIcons.skipForward));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byIcon(PhonoliteIcons.square));
        await tester.pump(const Duration(milliseconds: 250));
        expect(probe.playTaps, playback == 'idle' ? 0 : 1);
        expect(probe.nextTaps, playback == 'idle' ? 0 : 1);
        expect(probe.stopTaps, playback == 'idle' ? 0 : 1);
        expect(tester.takeException(), isNull);
      } finally {
        await probe.dispose(tester);
      }
    }, variant: desktopPlatforms);
  }

  testWidgets('short desktop windows scale the complete player and its page clearance together', (tester) async {
    final probe = (await tester.runAsync(() async => _PlayerProbe('server')))!;
    _configureView(tester);
    try {
      await _pumpScaffold(tester, probe, width: 1280);
      final baseline = _playerMeasurements(tester, 'server');
      final baselineHeight = tester.getSize(find.byType(NowPlayingBar)).height;

      await _pumpScaffold(tester, probe, width: 1280, height: 360);
      final resized = _playerMeasurements(tester, 'server');
      final player = tester.getRect(find.byType(NowPlayingBar));
      final ratio = resized['artwork']!.width / baseline['artwork']!.width;
      final inset = tester.widget<PlaybackContentInset>(find.byType(PlaybackContentInset));
      expect(ratio, lessThan(1));
      expect(player.height, closeTo(baselineHeight * ratio, 0.01));
      expect(inset.bottom, closeTo(player.height, 0.01));
      expect(player.bottom, closeTo(360, 0.01));

      for (final item in baseline.entries) {
        final actual = resized[item.key]!;
        expect(actual.width, closeTo(item.value.width * ratio, 0.01), reason: '${item.key} width');
        expect(actual.height, closeTo(item.value.height * ratio, 0.01), reason: '${item.key} height');
      }

      _expectDesktopLayout(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await probe.dispose(tester);
    }
  }, variant: desktopPlatforms);

  testWidgets('mobile windows retain phone chrome in landscape and adapt tablet split screen', (tester) async {
    final probe = (await tester.runAsync(() async => _PlayerProbe('local')))!;
    _configureView(tester);
    try {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final layout in [
          (size: const Size(390, 844), compact: true),
          (size: const Size(1200, 430), compact: true),
          (size: const Size(540, 900), compact: true),
          (size: const Size(768, 1024), compact: false),
          (size: const Size(1024, 768), compact: false),
        ]) {
          await _pumpScaffold(tester, probe, width: layout.size.width, height: layout.size.height, platform: platform);
          expect(find.byType(AppBottomNavigation), layout.compact ? findsOneWidget : findsNothing);
          expect(find.byType(AppSideNavigation), layout.compact ? findsNothing : findsOneWidget);
          expect(find.byType(NowPlayingMiniBar), layout.compact ? findsOneWidget : findsNothing);
          expect(find.byType(NowPlayingBar), layout.compact ? findsNothing : findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$platform at ${layout.size}');

          if (layout.size == const Size(1200, 430)) {
            tester.widget<NowPlayingMiniBar>(find.byType(NowPlayingMiniBar)).onExpand();
            await tester.pumpAndSettle();
            expect(find.byType(NowPlayingExpandedSheet), findsOneWidget);
            expect(tester.takeException(), isNull, reason: '$platform landscape phone player');
            Navigator.of(tester.element(find.byType(NowPlayingExpandedSheet))).pop();
            await tester.pumpAndSettle();
          }
        }
      }
    } finally {
      await probe.dispose(tester);
    }
  });

  testWidgets('narrow tablet player retains touch targets and working control edges', (tester) async {
    final probe = (await tester.runAsync(() async => _PlayerProbe('server')))!;
    _configureView(tester);
    try {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final size in const [Size(600, 900), Size(768, 1024), Size(979, 800)]) {
          await _pumpScaffold(tester, probe, width: size.width, height: size.height, platform: platform);
          expect(find.byType(NowPlayingBar), findsOneWidget);
          expect(find.byType(NowPlayingMiniBar), findsNothing);
          final player = tester.getRect(find.byType(NowPlayingBar));
          final inset = tester.widget<PlaybackContentInset>(find.byType(PlaybackContentInset));
          expect(inset.bottom, greaterThanOrEqualTo(player.height - 0.01));

          for (final control in [
            find.byIcon(PhonoliteIcons.shuffle),
            find.byIcon(PhonoliteIcons.skipBack),
            find.byIcon(Icons.play_arrow),
            find.byIcon(PhonoliteIcons.square),
            find.byIcon(PhonoliteIcons.skipForward),
            find.byIcon(PhonoliteIcons.repeat),
            find.byType(PlaylistAddIcon),
            find.byIcon(PhonoliteIcons.heart),
            find.byIcon(PhonoliteIcons.speaker),
            find.text('AUTO'),
          ]) {
            final target = _renderedRect(tester, _controlHitTarget(control));
            expect(target.width, greaterThanOrEqualTo(48 - 0.001), reason: '$control at $platform $size');
            expect(target.height, greaterThanOrEqualTo(48 - 0.001), reason: '$control at $platform $size');
            expect(target.left, greaterThanOrEqualTo(player.left));
            expect(target.right, lessThanOrEqualTo(player.right));
            expect(target.top, greaterThanOrEqualTo(player.top));
            expect(target.bottom, lessThanOrEqualTo(player.bottom));
          }

          final stop = _renderedRect(tester, _controlHitTarget(find.byIcon(PhonoliteIcons.square)));
          final previousStops = probe.stopTaps;
          await tester.tapAt(Offset(stop.left + 1, stop.center.dy));
          await tester.pump(const Duration(milliseconds: 250));
          expect(probe.stopTaps, previousStops + 1, reason: 'Stop target edge at $platform $size');

          final next = _renderedRect(tester, _controlHitTarget(find.byIcon(PhonoliteIcons.skipForward)));
          final previousNexts = probe.nextTaps;
          await tester.tapAt(Offset(next.right - 1, next.center.dy));
          await tester.pump(const Duration(milliseconds: 250));
          expect(probe.nextTaps, previousNexts + 1, reason: 'Next target edge at $platform $size');
          expect(tester.takeException(), isNull, reason: 'tablet player at $platform $size');
        }
      }
    } finally {
      await probe.dispose(tester);
    }
  });

  testWidgets('scaled desktop controls retain their rendered hit targets', (tester) async {
    final probe = (await tester.runAsync(() async => _PlayerProbe('server')))!;
    _configureView(tester);
    try {
      var expectedTaps = 0;
      for (final size in const [Size(980, 800), Size(600, 360)]) {
        await _pumpScaffold(tester, probe, width: size.width, height: size.height);

        final play = _renderedRect(tester, _controlHitTarget(find.byIcon(Icons.play_arrow)));
        final next = _renderedRect(tester, _controlHitTarget(find.byIcon(PhonoliteIcons.skipForward)));
        final like = _renderedRect(tester, _controlHitTarget(find.byIcon(PhonoliteIcons.heart)));
        await tester.tapAt(Offset(play.left + 1, play.center.dy));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tapAt(Offset(next.right - 1, next.center.dy));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tapAt(Offset(like.left + 1, like.center.dy));
        await tester.pump(const Duration(milliseconds: 250));
        expectedTaps++;

        expect(probe.playTaps, expectedTaps, reason: 'play target at $size');
        expect(probe.nextTaps, expectedTaps, reason: 'next target at $size');
        expect(probe.likeTaps, expectedTaps, reason: 'like target at $size');

        final volume = _renderedRect(tester, _volumeSlider());
        await tester.tapAt(Offset(volume.left + volume.width * 0.8, volume.center.dy));
        await tester.pump();
        expect(probe.lastVolume, isNotNull);
        expect(probe.lastVolume!, greaterThan(0.5));

        final seek = _renderedRect(tester, find.byWidgetPredicate((widget) => widget is Slider && widget.max > 1));
        await tester.tapAt(Offset(seek.left + seek.width * 0.75, seek.center.dy));
        await tester.pump();
        expect(probe.lastSeek?.inSeconds, inInclusiveRange(40, 50), reason: 'seek at $size');
        expect(tester.takeException(), isNull);
      }
    } finally {
      await probe.dispose(tester);
    }
  }, variant: desktopPlatforms);

  for (final layout in [
    (size: const Size(320, 568), textScale: 1.0),
    (size: const Size(390, 700), textScale: 1.0),
    (size: const Size(430, 932), textScale: 1.0),
    (size: const Size(320, 568), textScale: 1.4),
    (size: const Size(390, 844), textScale: 1.4),
  ]) {
    for (final playback in ['local', 'server']) {
      testWidgets('$playback mobile tray fits without scrolling at ${layout.size}, text scale ${layout.textScale}', (
        tester,
      ) async {
        final probe = (await tester.runAsync(() async => _PlayerProbe(playback)))!;
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
                        onVolumeChanged: (volume) => probe.lastVolume = volume,
                        onToggleMute: () {},
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
          final seek = find.byWidgetPredicate((widget) => widget is Slider && widget.max > 1);
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
                  find.descendant(of: sheet, matching: find.byType(SingleChildScrollView)),
                )
                .where((scroll) => scroll.scrollDirection == Axis.vertical),
            isEmpty,
          );
          expect(artRect.width, greaterThan(0));
          expect(artRect.left, greaterThanOrEqualTo(16));
          expect(artRect.right, lessThanOrEqualTo(layout.size.width - 16));
          expect(artRect.width, closeTo(artRect.height, 0.01));
          expect(artRect.top, greaterThanOrEqualTo(44 + 30 + 12));
          expect(artRect.bottom + 22, lessThanOrEqualTo(titleRect.top + 0.01));
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
            expect(controls[index].left, greaterThan(controls[index - 1].right));
          }
          final shuffle = tester.getRect(find.byIcon(PhonoliteIcons.shuffle));
          final device = tester.getRect(find.byIcon(PhonoliteIcons.speaker));
          expect(shuffle.top, greaterThan(controls.first.bottom));
          expect(shuffle.center.dy, closeTo(device.center.dy, 0.01));
          await tester.drag(art, const Offset(0, -80));
          await tester.pumpAndSettle();
          expect(tester.getRect(art), artRect);

          await tester.tapAt(Offset(seekRect.left + seekRect.width * 0.75, seekRect.center.dy));
          await tester.pump();
          expect(seekPosition?.inSeconds, inInclusiveRange(40, 50));
          await tester.tap(find.byIcon(Icons.play_arrow));
          await tester.tap(find.byIcon(PhonoliteIcons.square));
          await tester.tap(find.byIcon(PhonoliteIcons.skipBack));
          await tester.tap(find.byIcon(PhonoliteIcons.skipForward));
          await tester.tap(find.byIcon(PhonoliteIcons.repeat));
          expect([probe.playTaps, probe.stopTaps, probe.prevTaps, probe.nextTaps, probe.repeatTaps], everyElement(1));
          expect(tester.takeException(), isNull);
        } finally {
          await probe.dispose(tester);
        }
      });
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
  double height = 800,
  TargetPlatform? platform,
}) async {
  final size = Size(width, height);
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    AppScope(
      controller: probe.controller,
      child: MaterialApp(
        theme: ObsidianTheme.build().copyWith(platform: platform ?? defaultTargetPlatform),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: ObsidianScale(
            scale: ObsidianScale.compute(width),
            child: AdaptiveScaffold(
              destinations: const [
                NavigationDestination(icon: Icon(PhonoliteIcons.disc3), label: 'Library'),
                NavigationDestination(icon: Icon(Icons.list), label: 'Playlists'),
                NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Liked'),
                NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
                NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              page: const SizedBox.expand(),
              playbackState: probe.state,
              onOpenAlbum: _noop,
              onPlayPause: () => probe.playTaps++,
              onNext: () => probe.nextTaps++,
              onPrev: _noop,
              onStop: () => probe.stopTaps++,
              onSeek: (position) => probe.lastSeek = position,
              onSeekPreview: (_) {},
              onShuffleChanged: (_, {scope}) {},
              onToggleRepeat: _noop,
              onStreamModeChanged: (_) {},
              onVolumeChanged: (value) => probe.lastVolume = value,
              onToggleMute: () {},
              onToggleLike: () => probe.likeTaps++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectDesktopLayout(WidgetTester tester) {
  expect(find.byType(PlaybackIntelZone), findsOneWidget);
  expect(find.byType(PlaybackCommandZone), findsOneWidget);
  expect(find.byType(PlaybackOutputZone), findsOneWidget);
  expect(find.byType(PlaybackCompactControls), findsNothing);
  expect(find.byType(PlaybackCompactFooterRow), findsNothing);

  final player = tester.getRect(find.byType(NowPlayingBar));
  final metadata = _renderedRect(tester, find.byType(PlaybackIntelZone));
  final transport = _renderedRect(tester, find.byType(PlaybackCommandZone));
  final output = _renderedRect(tester, find.byType(PlaybackOutputZone));
  final progress = _renderedRect(tester, find.byType(PlaybackProgressBar));
  expect(metadata.right, lessThan(transport.left));
  expect(transport.right, lessThan(output.left));
  expect(metadata.width, closeTo(output.width, 0.01));
  expect(transport.center.dx, closeTo(player.center.dx, 0.01));
  expect(progress.top, greaterThanOrEqualTo(transport.bottom - 0.01));
  expect(progress.bottom, lessThanOrEqualTo(player.bottom));
  expect(find.descendant(of: find.byType(PlaybackOutputZone), matching: find.byType(Wrap)), findsNothing);

  final transportIcons = [
    PhonoliteIcons.shuffle,
    PhonoliteIcons.skipBack,
    Icons.play_arrow,
    PhonoliteIcons.square,
    PhonoliteIcons.skipForward,
    PhonoliteIcons.repeat,
  ].map((icon) => _renderedRect(tester, find.byIcon(icon))).toList();
  for (var index = 0; index < transportIcons.length; index++) {
    final icon = transportIcons[index];
    expect(icon.center.dy, closeTo(transportIcons.first.center.dy, 0.01));
    expect(icon.left, greaterThanOrEqualTo(transport.left));
    expect(icon.right, lessThanOrEqualTo(transport.right));
    if (index > 0) {
      expect(icon.left, greaterThan(transportIcons[index - 1].right));
    }
  }

  final outputControls = [
    find.byType(PlaylistAddIcon),
    find.byIcon(PhonoliteIcons.heart),
    find.byIcon(PhonoliteIcons.speaker),
  ].map((finder) => _renderedRect(tester, finder)).toList();
  for (var index = 0; index < outputControls.length; index++) {
    final control = outputControls[index];
    expect(control.center.dy, closeTo(outputControls.first.center.dy, 0.01));
    expect(control.left, greaterThanOrEqualTo(output.left));
    expect(control.right, lessThanOrEqualTo(output.right));
    if (index > 0) {
      expect(control.left, greaterThan(outputControls[index - 1].right));
    }
  }

  expect(_renderedRect(tester, _volumeSlider()).top, greaterThan(outputControls.first.bottom));
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
    'elapsed time': find.text('0:00'),
    'duration': find.text('1:00'),
  };
  if (playback == 'server') {
    measurements['location tag'] = find.text('SERVER');
    expect(find.text('LOCAL'), findsNothing);
    measurements['source tag'] = find.text('LIKED TRACKS');
    measurements['quality text'] = find.text('AUTO');
    measurements['quality button'] = find
        .ancestor(of: find.text('AUTO'), matching: find.byType(AnimatedContainer))
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
  return {for (final item in measurements.entries) item.key: _renderedRect(tester, item.value)};
}

Finder _volumeSlider() {
  final volumeRow = find.ancestor(of: find.byIcon(PhonoliteIcons.volume2), matching: find.byType(Row)).first;
  return find.descendant(of: volumeRow, matching: find.byType(Slider));
}

Finder _controlHitTarget(Finder control) => find.ancestor(of: control, matching: find.byType(GestureDetector)).first;

Rect _renderedRect(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final box = tester.renderObject<RenderBox>(finder);
  // getSize reports layout dimensions before ancestor transforms. Measure
  // the visible rectangle instead, including the fitted player's scale.
  return Rect.fromPoints(box.localToGlobal(Offset.zero), box.localToGlobal(box.size.bottomRight(Offset.zero)));
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
      localPlaybackSource: playback == 'local' ? LocalPlaybackSource.library : LocalPlaybackSource.none,
      isLocalPlayback: playback == 'local',
    );
  }

  final controller = AppController(connection: ServerConnection(baseUrl: 'http://server.test/api'));
  late final PlaybackState state;
  int playTaps = 0;
  int nextTaps = 0;
  int prevTaps = 0;
  int stopTaps = 0;
  int repeatTaps = 0;
  int likeTaps = 0;
  double? lastVolume;
  Duration? lastSeek;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(controller.close);
  }
}

void _noop() {}

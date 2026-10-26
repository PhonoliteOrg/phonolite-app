import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';
import 'package:phonolite_app/ui/navigation/retained_tab_view.dart';
import 'package:phonolite_app/ui/shell/adaptive_scaffold.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';

import '../support/widget_test_helpers.dart';

const _viewportKey = ValueKey('page-viewport');
const _finalRowKey = ValueKey('final-row');
const _firstRowKey = ValueKey('first-row');
const _safeAreaBottom = 24.0;
const _navigationHeight = 64.0;

void main() {
  setUpAll(configureTestFonts);

  for (final layout in const [
    (size: Size(375, 667), topInset: 20.0),
    (size: Size(390, 844), topInset: 44.0),
    (size: Size(430, 932), topInset: 59.0),
    (size: Size(402, 874), topInset: 62.0),
    (size: Size(1024, 800), topInset: 24.0),
  ]) {
    final size = layout.size;
    final topInset = layout.topInset;
    for (final hiddenPlayer in [false, true]) {
      testWidgets(
        'iOS viewport fills $size with safe controls, hidden player: $hiddenPlayer',
        (tester) async {
          final probe = (await tester.runAsync(() async => _LayoutProbe()))!;
          final compact = size.width < 980;
          try {
            await _pumpLayout(
              tester,
              probe: probe,
              size: size,
              platform: TargetPlatform.iOS,
              safeAreaTop: topInset,
              hidePlaybackChrome: hiddenPlayer,
            );
            expect(
              tester.getRect(find.byKey(_viewportKey)),
              Rect.fromLTWH(
                compact ? 0 : 64,
                0,
                size.width - (compact ? 0 : 64),
                size.height,
              ),
            );
            expect(probe.pagePadding.top, 0);
            expect(probe.pagePadding.bottom, 0);
            expect(probe.topInset, topInset);
            expect(tester.getRect(find.byKey(_firstRowKey)).top, topInset);

            final player = find.byType(
              compact ? NowPlayingMiniBar : NowPlayingBar,
            );
            final navigation = find.byType(ObsidianNavIcon);
            if (compact) {
              final glass = find.ancestor(
                of: navigation,
                matching: find.byType(ObsidianGlassSurface),
              );
              expect(tester.getRect(glass).bottom, size.height);
              expect(
                tester.getRect(navigation).bottom,
                lessThanOrEqualTo(size.height - _safeAreaBottom),
              );
            } else {
              expect(
                tester.getRect(navigation).top,
                greaterThanOrEqualTo(topInset),
              );
            }
            final clearBottom = hiddenPlayer
                ? size.height -
                      (compact
                          ? _navigationHeight + _safeAreaBottom
                          : _safeAreaBottom)
                : tester.getRect(player).top;
            probe.scroll.jumpTo(topInset / 2);
            await tester.pump();
            final scrolledTop = tester.getRect(find.byKey(_firstRowKey)).top;
            expect(scrolledTop, inExclusiveRange(0, topInset));

            probe.scroll.jumpTo(probe.scroll.position.maxScrollExtent);
            await tester.pump();
            expect(
              tester.getRect(find.byKey(_finalRowKey)).bottom,
              closeTo(clearBottom, 0.01),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await probe.dispose(tester);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }

  for (final size in const [Size(430, 800), Size(1024, 800)]) {
    for (final hiddenPlayer in [false, true]) {
      testWidgets(
        'Android content scrolls behind status bar at $size, hidden player: $hiddenPlayer',
        (tester) async {
          final probe = (await tester.runAsync(() async => _LayoutProbe()))!;
          final compact = size.width < 980;
          const topInset = 24.0;
          try {
            await _pumpLayout(
              tester,
              probe: probe,
              size: size,
              platform: TargetPlatform.android,
              safeAreaTop: topInset,
              hidePlaybackChrome: hiddenPlayer,
            );

            final viewport = tester.getRect(find.byKey(_viewportKey));
            expect(viewport.top, 0);
            expect(viewport.bottom, size.height - (compact ? _navigationHeight + _safeAreaBottom : 0));
            expect(probe.pagePadding.top, 0);
            expect(probe.pagePadding.bottom, 0);
            expect(probe.topInset, topInset);
            expect(tester.getRect(find.byKey(_firstRowKey)).top, topInset);

            probe.scroll.jumpTo(topInset / 2);
            await tester.pump();
            expect(tester.getRect(find.byKey(_firstRowKey)).top, inExclusiveRange(0, topInset));

            final clearBottom = hiddenPlayer
                ? viewport.bottom
                : tester.getRect(find.byType(compact ? NowPlayingMiniBar : NowPlayingBar)).top;
            probe.scroll.jumpTo(probe.scroll.position.maxScrollExtent);
            await tester.pump();
            expect(tester.getRect(find.byKey(_finalRowKey)).bottom, closeTo(clearBottom, 0.01));
            expect(tester.takeException(), isNull);
          } finally {
            await probe.dispose(tester);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  for (final layout in const [
    (name: 'wide', size: Size(1280, 800), compact: false),
    (name: 'compact', size: Size(430, 800), compact: true),
  ]) {
    testWidgets(
      '${layout.name} page extends beneath player and scrolls its final row clear',
      (tester) async {
        final probe = (await tester.runAsync(() async => _LayoutProbe()))!;
        try {
          await _pumpLayout(tester, probe: probe, size: layout.size);
          final player = find.byType(
            layout.compact ? NowPlayingMiniBar : NowPlayingBar,
          );
          final playerRect = tester.getRect(player);
          final viewportRect = tester.getRect(find.byKey(_viewportKey));
          final expectedBottom =
              layout.size.height -
              (layout.compact ? _navigationHeight + _safeAreaBottom : 0);

          expect(viewportRect.bottom, closeTo(expectedBottom, 0.01));
          expect(viewportRect.bottom, greaterThan(playerRect.top));
          expect(viewportRect.bottom, closeTo(playerRect.bottom, 0.01));
          expect(probe.playbackInset, closeTo(playerRect.height, 0.01));
          expect(probe.pagePadding.bottom, 0);

          _expectTranslucentWindowsBackdrop(tester, player);

          probe.scroll.jumpTo(probe.scroll.position.maxScrollExtent);
          await tester.pump();

          final finalRowRect = tester.getRect(find.byKey(_finalRowKey));
          expect(finalRowRect.top, greaterThanOrEqualTo(viewportRect.top));
          expect(finalRowRect.bottom, lessThanOrEqualTo(playerRect.top + 0.01));
          expect(finalRowRect.bottom, closeTo(playerRect.top, 0.01));
          expect(tester.takeException(), isNull);
        } finally {
          await probe.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      '${layout.name} hidden player leaves no playback clearance',
      (tester) async {
        final probe = (await tester.runAsync(() async => _LayoutProbe()))!;
        try {
          await _pumpLayout(
            tester,
            probe: probe,
            size: layout.size,
            hidePlaybackChrome: true,
          );
          final viewportRect = tester.getRect(find.byKey(_viewportKey));
          final expectedBottom =
              layout.size.height -
              (layout.compact ? _navigationHeight + _safeAreaBottom : 0);

          expect(find.byType(NowPlayingBar), findsNothing);
          expect(find.byType(NowPlayingMiniBar), findsNothing);
          expect(probe.playbackInset, 0);
          expect(probe.pagePadding.bottom, 0);
          expect(viewportRect.bottom, closeTo(expectedBottom, 0.01));

          probe.scroll.jumpTo(probe.scroll.position.maxScrollExtent);
          await tester.pump();

          expect(
            tester.getRect(find.byKey(_finalRowKey)).bottom,
            closeTo(viewportRect.bottom, 0.01),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await probe.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

Future<void> _pumpLayout(
  WidgetTester tester, {
  required _LayoutProbe probe,
  required Size size,
  bool hidePlaybackChrome = false,
  TargetPlatform platform = TargetPlatform.windows,
  double safeAreaTop = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    AppScope(
      controller: probe.controller,
      child: MaterialApp(
        theme: ObsidianTheme.build().copyWith(platform: platform),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(top: safeAreaTop, bottom: _safeAreaBottom),
            viewPadding: EdgeInsets.only(
              top: safeAreaTop,
              bottom: _safeAreaBottom,
            ),
          ),
          child: ObsidianScale(
            scale: ObsidianScale.compute(size.width),
            child: AdaptiveScaffold(
              destinations: const [
                NavigationDestination(
                  icon: Icon(PhonoliteIcons.disc3),
                  label: 'Library',
                ),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              page: RetainedTabView(
                index: 0,
                children: [
                  Builder(
                    builder: (context) {
                      probe.playbackInset = PlaybackContentInset.bottomOf(
                        context,
                      );
                      probe.topInset = PlaybackContentInset.topOf(context);
                      probe.pagePadding = MediaQuery.paddingOf(context);
                      return ColoredBox(
                        key: _viewportKey,
                        color: Colors.deepPurple,
                        child: CustomScrollView(
                          controller: probe.scroll,
                          slivers: [
                            const SliverPageTopInset(),
                            SliverFixedExtentList(
                              itemExtent: 80,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => ColoredBox(
                                  key: index == 31
                                      ? _finalRowKey
                                      : index == 0
                                      ? _firstRowKey
                                      : null,
                                  color: index.isEven
                                      ? Colors.blue
                                      : Colors.teal,
                                  child: Center(child: Text('Row $index')),
                                ),
                                childCount: 32,
                              ),
                            ),
                            const SliverPlaybackInset(),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              playbackState: probe.controller.playbackState,
              onOpenAlbum: _noop,
              onPlayPause: _noop,
              onNext: _noop,
              onPrev: _noop,
              onStop: _noop,
              onSeek: (_) {},
              onSeekPreview: (_) {},
              onShuffleChanged: (_, {scope}) {},
              onToggleRepeat: _noop,
              onStreamModeChanged: (_) {},
              onVolumeChanged: (_) {},
              onToggleLike: _noop,
              hidePlaybackChrome: hidePlaybackChrome,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectTranslucentWindowsBackdrop(WidgetTester tester, Finder player) {
  // Windows keeps the bar's glass without a second blur inside each play button.
  expect(
    find.descendant(of: player, matching: find.byType(BackdropFilter)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: player,
      matching: find.byWidgetPredicate(
        (widget) => widget is BackdropFilter && widget.child is DecoratedBox,
      ),
    ),
    findsOneWidget,
  );
  final gradients = tester
      .widgetList<DecoratedBox>(
        find.descendant(of: player, matching: find.byType(DecoratedBox)),
      )
      .map((widget) => widget.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.gradient)
      .whereType<LinearGradient>()
      .where(
        (gradient) =>
            gradient.begin == Alignment.topCenter &&
            gradient.end == Alignment.bottomCenter &&
            gradient.colors.every((color) => color.a < 1.0) &&
            gradient.colors.toSet().length > 1,
      );
  expect(gradients, isNotEmpty);
}

class _LayoutProbe {
  final controller = AppController(
    connection: ServerConnection(baseUrl: 'http://server.test/api'),
  );
  final scroll = ScrollController();
  double playbackInset = -1;
  double topInset = -1;
  EdgeInsets pagePadding = EdgeInsets.zero;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // MarqueeText's startup delay must finish before widget-test invariants run.
    await tester.pump(const Duration(seconds: 1));
    scroll.dispose();
    await tester.runAsync(controller.close);
  }
}

void _noop() {}

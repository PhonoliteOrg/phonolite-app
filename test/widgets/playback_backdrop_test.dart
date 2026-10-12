import 'package:flutter/material.dart';

import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/widgets/display/now_playing_bar.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/layouts/playback_content_inset.dart';
import 'package:phonolite_app/widgets/navigation/adaptive_scaffold.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

const _viewportKey = ValueKey('page-viewport');
const _finalRowKey = ValueKey('final-row');
const _safeAreaBottom = 24.0;
const _navigationHeight = 64.0;

void main() {
  setUpAll(configureTestFonts);

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
        theme: ObsidianTheme.build().copyWith(platform: TargetPlatform.windows),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(bottom: _safeAreaBottom),
            viewPadding: const EdgeInsets.only(bottom: _safeAreaBottom),
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
              page: Builder(
                builder: (context) {
                  probe.playbackInset = PlaybackContentInset.bottomOf(context);
                  probe.pagePadding = MediaQuery.paddingOf(context);
                  return ColoredBox(
                    key: _viewportKey,
                    color: Colors.deepPurple,
                    child: CustomScrollView(
                      controller: probe.scroll,
                      slivers: [
                        SliverFixedExtentList(
                          itemExtent: 80,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => ColoredBox(
                              key: index == 31 ? _finalRowKey : null,
                              color: index.isEven ? Colors.blue : Colors.teal,
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
    connection: ServerConnection(baseUrl: 'http://server.test/api/v1'),
  );
  final scroll = ScrollController();
  double playbackInset = -1;
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

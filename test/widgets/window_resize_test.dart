import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_viewport.dart';
import 'package:phonolite_app/widgets/layouts/retained_tab_view.dart';
import 'package:phonolite_app/widgets/ui/obsidian_theme.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets(
    'theme cache reuses the current scale and respects the platform',
    (tester) async {
      final full = ObsidianTheme.build();
      expect(ObsidianTheme.build(), same(full));
      final small = ObsidianTheme.build(scale: 0.8);
      expect(ObsidianTheme.build(scale: 0.8), same(small));
      expect(ObsidianTheme.build(), full);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(ObsidianTheme.build().platform, TargetPlatform.iOS);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(ObsidianTheme.build().platform, TargetPlatform.windows);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'resizing keeps a stable theme and applies small sizes immediately',
    (tester) async {
      _configureView(tester);
      var builds = 0;
      var scale = 0.0;
      ThemeData? theme;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              builds++;
              scale = ObsidianScale.of(context);
              theme = Theme.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialTheme = theme;
      final initialBuilds = builds;
      final initialFontSize = theme!.textTheme.bodyMedium!.fontSize!;

      for (final size in const [
        Size(1279, 720),
        Size(1100, 740),
        Size(980, 710),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(theme, same(initialTheme));
        expect(builds, initialBuilds);
      }
      for (final width in const [899.0, 880.0, 740.0, 630.0, 430.0]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pump();
        final expectedScale = ObsidianScale.compute(width);
        expect(scale, expectedScale);
        expect(
          theme!.textTheme.bodyMedium!.fontSize,
          closeTo(initialFontSize * expectedScale, 0.001),
        );
        expect(find.byType(AnimatedTheme), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'resizing lays out only the active retained tab',
    (tester) async {
      _configureView(tester);
      final layouts = List.filled(5, 0);
      final states = List.generate(5, (_) => GlobalKey<_TabProbeState>());
      final children = List.generate(
        5,
        (index) =>
            _TabProbe(key: states[index], onLayout: () => layouts[index]++),
      );
      final tabKey = GlobalKey();

      // Visit every tab so this also tests previously laid-out hidden subtrees.
      for (var index = 0; index < children.length; index++) {
        await tester.pumpWidget(
          _app(RetainedTabView(key: tabKey, index: index, children: children)),
        );
        await tester.pumpAndSettle();
        expect(states[index].currentState, isNotNull);
      }
      final retainedStates = states.map((key) => key.currentState).toList();
      for (final size in const [
        Size(1100, 740),
        Size(880, 720),
        Size(740, 710),
        Size(1280, 720),
      ]) {
        final before = List.of(layouts);
        tester.view.physicalSize = size;
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          expect(layouts[i], before[i], reason: 'Hidden tab $i at $size');
        }
        expect(layouts[4], greaterThan(before[4]));
        expect(states.map((key) => key.currentState).toList(), retainedStates);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'tab routes survive switching and scaffold breakpoint changes',
    (tester) async {
      _configureView(tester);
      final tabKey = GlobalKey();
      final navigators = List.generate(2, (_) => GlobalKey<NavigatorState>());
      final children = List.generate(
        2,
        (index) => Navigator(
          key: navigators[index],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Center(child: Text('Root $index')),
          ),
        ),
      );
      Widget shell(int index) => _app(
        LayoutBuilder(
          builder: (context, constraints) {
            final tabs = RetainedTabView(
              key: tabKey,
              index: index,
              children: children,
            );
            return constraints.maxWidth >= 980
                ? Row(
                    children: [
                      const SizedBox(width: 64),
                      Expanded(child: tabs),
                    ],
                  )
                : Stack(children: [Positioned.fill(child: tabs)]);
          },
        ),
      );
      await tester.pumpWidget(shell(0));
      await tester.pumpAndSettle();
      final firstNavigator = navigators[0].currentState!;
      firstNavigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Center(child: Text('Detail 0')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(shell(1));
      await tester.pumpAndSettle();
      expect(find.text('Root 1'), findsOneWidget);
      expect(find.text('Detail 0'), findsNothing);
      for (final width in const [979.0, 740.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpAndSettle();
        expect(navigators[0].currentState, same(firstNavigator));
      }
      await tester.pumpWidget(shell(0));
      await tester.pumpAndSettle();
      expect(find.text('Detail 0'), findsOneWidget);
      expect(firstNavigator.canPop(), isTrue);
      firstNavigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Root 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('hidden tabs suspend tickers and cannot take keyboard focus', (
    tester,
  ) async {
    _configureView(tester);
    final ticks = List.filled(2, 0);
    final focusNodes = List.generate(2, (_) => FocusNode());
    final tabKey = GlobalKey();
    final children = List.generate(
      2,
      (index) => _TickerProbe(
        onTick: () => ticks[index]++,
        focusNode: focusNodes[index],
      ),
    );
    await tester.pumpWidget(
      _app(RetainedTabView(key: tabKey, index: 0, children: children)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(ticks[0], greaterThan(0));
    expect(ticks[1], 0);
    expect(focusNodes[0].canRequestFocus, isTrue);
    expect(focusNodes[1].canRequestFocus, isFalse);

    await tester.pumpWidget(
      _app(RetainedTabView(key: tabKey, index: 1, children: children)),
    );
    final inactiveTicks = ticks[0];
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(ticks[0], inactiveTicks);
    expect(ticks[1], greaterThan(0));
    expect(focusNodes[0].canRequestFocus, isFalse);
    expect(focusNodes[1].canRequestFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final node in focusNodes) {
      node.dispose();
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ObsidianTheme.build(),
  themeAnimationStyle: AnimationStyle.noAnimation,
  builder: (context, child) => ObsidianViewport(child: child!),
  home: child,
);

void _configureView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _TabProbe extends StatefulWidget {
  const _TabProbe({super.key, required this.onLayout});

  final VoidCallback onLayout;

  @override
  State<_TabProbe> createState() => _TabProbeState();
}

class _TabProbeState extends State<_TabProbe> {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final scale = ObsidianScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.onLayout();
        return Center(child: Text('Scale $scale', style: style));
      },
    );
  }
}

class _TickerProbe extends StatefulWidget {
  const _TickerProbe({required this.onTick, required this.focusNode});

  final VoidCallback onTick;
  final FocusNode focusNode;

  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() => widget.onTick());
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focusNode, child: const SizedBox.expand());
}

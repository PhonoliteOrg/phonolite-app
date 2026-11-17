import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/navigation/desktop_mouse_navigation.dart';
import 'package:phonolite_app/ui/navigation/menu_navigation_history.dart';
import 'package:phonolite_app/ui/navigation/retained_tab_view.dart';

void main() {
  const desktops = TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux});

  testWidgets('macOS trackpad swipes navigate back and forward once per gesture', (tester) async {
    final menu = await _pumpMenu(tester);
    final navigator = menu.navigators[0].currentState!;
    navigator.push<void>(_page('Artist'));
    navigator.push<void>(_page('Album'));
    await tester.pumpAndSettle();

    await _swipe(tester, const Offset(160, 10));
    expect(find.text('Artist'), findsOneWidget);
    await _swipe(tester, const Offset(-160, 10));
    expect(find.text('Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('small, vertical, diagonal, zoom and rotate gestures stay on the page', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(_page('Album'));
    await tester.pumpAndSettle();

    await _swipe(tester, const Offset(40, 0));
    await _swipe(tester, const Offset(10, 160));
    await _swipe(tester, const Offset(160, 100));
    await _swipe(tester, const Offset(160, 0), scale: 1.25);
    await _swipe(tester, const Offset(160, 0), rotation: 0.1);
    expect(find.text('Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('macOS trackpad scrolling takes precedence over page navigation', (tester) async {
    final menu = await _pumpMenu(tester);
    final navigator = menu.navigators[0].currentState!;

    for (final axis in Axis.values) {
      final scroll = ScrollController(initialScrollOffset: 200);
      addTearDown(scroll.dispose);
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ListView.builder(
              controller: scroll,
              scrollDirection: axis,
              itemExtent: 100,
              itemCount: 20,
              itemBuilder: (_, index) => Text('Item $index'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _swipe(tester, axis == Axis.horizontal ? const Offset(160, 0) : const Offset(0, 160));
      expect(scroll.offset, lessThan(200));
      expect(navigator.canPop(), isTrue);

      if (axis == Axis.vertical) {
        await _swipe(tester, const Offset(160, 0));
        expect(find.text('Root 0'), findsOneWidget);
      } else {
        navigator.pop();
        await tester.pumpAndSettle();
      }
    }

    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('trackpad swipes are scoped to macOS', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(_page('Album'));
    await tester.pumpAndSettle();

    await _swipe(tester, const Offset(160, 0));
    expect(find.text('Album'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.iOS}));

  testWidgets('side buttons follow the menu back stack and forward history', (tester) async {
    final menu = await _pumpMenu(tester);
    final navigator = menu.navigators[0].currentState!;

    await _click(tester, kBackMouseButton);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Root 0'), findsOneWidget);

    navigator.push<void>(_page('Artist'));
    navigator.push<void>(_page('Album'));
    await tester.pumpAndSettle();

    await _click(tester, kBackMouseButton);
    expect(find.text('Artist'), findsOneWidget);
    await _click(tester, kBackMouseButton);
    expect(find.text('Root 0'), findsOneWidget);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Artist'), findsOneWidget);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Album'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Album')))!.settings.name, 'Album');
    await _click(tester, kForwardMouseButton);
    expect(find.text('Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktops);

  testWidgets('on-screen Back also allows Forward; a new page clears it', (tester) async {
    final menu = await _pumpMenu(tester);
    final navigator = menu.navigators[0].currentState!;
    navigator.push<void>(_page('Album'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to menu'));
    await tester.pumpAndSettle();
    await _click(tester, kForwardMouseButton);
    expect(find.text('Album'), findsOneWidget);

    await _click(tester, kBackMouseButton);
    navigator.push<void>(_page('Another album'));
    await tester.pumpAndSettle();
    await _click(tester, kForwardMouseButton);
    expect(find.text('Another album'), findsOneWidget);
    await _click(tester, kBackMouseButton);
    await _click(tester, kForwardMouseButton);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Another album'), findsOneWidget);
  }, variant: desktops);

  testWidgets('only the active tab moves and each tab keeps forward history', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(_page('Artist'));
    await tester.pumpAndSettle();
    menu.selected.value = 1;
    await tester.pumpAndSettle();
    menu.navigators[1].currentState!.push<void>(_page('Logs'));
    await tester.pumpAndSettle();
    await _click(tester, kBackMouseButton);
    expect(find.text('Root 1'), findsOneWidget);

    menu.selected.value = 0;
    await tester.pumpAndSettle();
    expect(find.text('Artist'), findsOneWidget);
    await _click(tester, kBackMouseButton);
    expect(find.text('Root 0'), findsOneWidget);

    menu.selected.value = 1;
    await tester.pumpAndSettle();
    await _click(tester, kForwardMouseButton);
    expect(find.text('Logs'), findsOneWidget);
    menu.selected.value = 0;
    await tester.pumpAndSettle();
    await _click(tester, kForwardMouseButton);
    expect(find.text('Artist'), findsOneWidget);
  }, variant: desktops);

  testWidgets('dialogs block page navigation and are excluded from history', (tester) async {
    final menu = await _pumpMenu(tester);
    final navigator = menu.navigators[0].currentState!;
    navigator.push<void>(_page('Album'));
    await tester.pumpAndSettle();
    await _click(tester, kBackMouseButton);
    final context = tester.element(find.text('Root 0'));

    // The dialog stays open while the test drives it.
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Root dialog')),
      ),
    );
    await tester.pumpAndSettle();
    final rootDialogPosition = tester.getCenter(find.text('Root dialog'));
    await _click(tester, kForwardMouseButton, position: rootDialogPosition);
    await _click(tester, kBackMouseButton, position: rootDialogPosition);
    expect(find.text('Root dialog'), findsOneWidget);
    menu.root.currentState!.pop();
    await tester.pumpAndSettle();

    // The dialog stays open while the test drives it.
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => const AlertDialog(content: Text('Tab dialog')),
      ),
    );
    await tester.pumpAndSettle();
    final tabDialogPosition = tester.getCenter(find.text('Tab dialog'));
    await _click(tester, kForwardMouseButton, position: tabDialogPosition);
    expect(find.text('Tab dialog'), findsOneWidget);
    await _click(tester, kBackMouseButton, position: tabDialogPosition);
    expect(find.text('Tab dialog'), findsNothing);
    expect(find.text('Root 0'), findsOneWidget);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Album'), findsOneWidget);
    await _click(tester, kForwardMouseButton);
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: desktops);

  testWidgets('Back honors a page that blocks popping', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PopScope(
          canPop: false,
          child: Scaffold(body: Center(child: Text('Stay here'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _click(tester, kBackMouseButton);
    await _click(tester, kForwardMouseButton);
    expect(find.text('Stay here'), findsOneWidget);
  }, variant: desktops);

  testWidgets('normal mouse buttons and non-mouse pointers do not navigate', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(_page('Album'));
    await tester.pumpAndSettle();
    for (final buttons in [
      kPrimaryMouseButton,
      kSecondaryMouseButton,
      kMiddleMouseButton,
      kBackMouseButton | kForwardMouseButton,
      kPrimaryMouseButton | kBackMouseButton,
    ]) {
      await _click(tester, buttons);
      expect(find.text('Album'), findsOneWidget);
    }
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
      await _click(tester, kBackMouseButton, kind: kind);
      expect(find.text('Album'), findsOneWidget);
    }
  }, variant: desktops);

  testWidgets('mouse side buttons are limited to desktop platforms', (tester) async {
    final menu = await _pumpMenu(tester);
    menu.navigators[0].currentState!.push<void>(_page('Album'));
    await tester.pumpAndSettle();
    await _click(tester, kBackMouseButton);
    expect(find.text('Album'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}

MaterialPageRoute<void> _page(String name) => MaterialPageRoute<void>(
  settings: RouteSettings(name: name),
  builder: (context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to menu')),
        ],
      ),
    ),
  ),
);

typedef _Menu = ({
  List<GlobalKey<NavigatorState>> navigators,
  GlobalKey<NavigatorState> root,
  ValueNotifier<int> selected,
});

Future<_Menu> _pumpMenu(WidgetTester tester) async {
  final root = GlobalKey<NavigatorState>();
  final navigators = List.generate(2, (_) => GlobalKey<NavigatorState>());
  final histories = List.generate(2, (_) => MenuNavigationHistory());
  final selected = ValueNotifier(0);
  addTearDown(selected.dispose);
  final tabs = List.generate(
    2,
    (index) =>
        Navigator(key: navigators[index], observers: [histories[index]], onGenerateRoute: (_) => _page('Root $index')),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: root,
      home: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (_, index, _) => DesktopMouseNavigation(
          onBack: histories[index].goBack,
          onForward: histories[index].goForward,
          child: RetainedTabView(index: index, children: tabs),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (navigators: navigators, root: root, selected: selected);
}

Future<void> _click(
  WidgetTester tester,
  int buttons, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  Offset position = const Offset(10, 10),
}) async {
  final gesture = await tester.startGesture(position, kind: kind, buttons: buttons);
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _swipe(WidgetTester tester, Offset pan, {double scale = 1, double rotation = 0}) async {
  const position = Offset(100, 100);
  final gesture = await tester.startGesture(position, kind: PointerDeviceKind.trackpad);

  for (var step = 1; step <= 4; step++) {
    await gesture.panZoomUpdate(
      position,
      pan: pan * (step / 4),
      scale: scale,
      rotation: rotation,
      timeStamp: Duration(milliseconds: step * 16),
    );
  }

  await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

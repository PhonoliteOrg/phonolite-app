import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/structures/collections/viewport_item.dart';

Widget _library(ScrollController controller, Set<int> active, {bool enabled = true}) => MaterialApp(
  home: Scaffold(
    body: TickerMode(
      enabled: enabled,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 300,
          child: CustomScrollView(
            controller: controller,
            scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
            slivers: [
              SliverList.builder(
                itemCount: 5000,
                itemBuilder: (context, index) => SizedBox(
                  height: 100,
                  child: ViewportItem(
                    key: ValueKey(index),
                    onVisibilityChanged: (visible) => visible ? active.add(index) : active.remove(index),
                    builder: (context, visible) => Text('$index: $visible'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('only viewport children activate in a 5000-artist collection', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final active = <int>{};
    await tester.pumpWidget(_library(controller, active));
    await tester.pump();
    expect(active, {0, 1, 2});
    expect(
      find.byType(ViewportItem, skipOffstage: false),
      findsAtLeastNWidgets(10),
      reason: 'Cached children must not activate work.',
    );

    controller.jumpTo(1000);
    await tester.pump();
    await tester.pump();
    expect(active, {10, 11, 12});
    await tester.pumpWidget(const SizedBox());
    expect(active, isEmpty);
  });

  testWidgets('new tiles activate during a drag and hidden pages release tiles', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final active = <int>{};
    await tester.pumpWidget(_library(controller, active));
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(100, 250));
    await gesture.moveBy(const Offset(0, -210));
    await tester.pump();

    expect(controller.position.isScrollingNotifier.value, isTrue);
    expect(active, containsAll([3, 4]));
    expect(active, isNot(contains(6)));

    await tester.pumpWidget(_library(controller, active, enabled: false));
    await tester.pump();
    expect(active, isEmpty);
    await gesture.cancel();
  });

  testWidgets('fast scrolling defers new tiles until it slows while still moving', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final active = <int>{};
    await tester.pumpWidget(_library(controller, active));
    await tester.pump();

    final motion = controller.animateTo(1800, duration: const Duration(seconds: 1), curve: Curves.easeOutCubic);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.position.isScrollingNotifier.value, isTrue);
    expect(active, isEmpty);

    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    expect(active, isNotEmpty);
    expect(
      active.every((index) => index * 100 < controller.offset + 300 && (index + 1) * 100 > controller.offset),
      isTrue,
    );

    await tester.pumpAndSettle();
    await motion;
    expect(active, {18, 19, 20});
  });
}

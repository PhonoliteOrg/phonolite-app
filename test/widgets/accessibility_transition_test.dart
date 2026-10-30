import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/navigation/retained_tab_view.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_slider_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

import '../support/accessibility_update_binding.dart';
import '../support/widget_test_helpers.dart';

void main() {
  final binding = AccessibilityUpdateBinding();

  setUp(() {
    configureTestFonts();
    binding.resetAccessibilityTree();

    final semantics = binding.ensureSemantics();

    addTearDown(semantics.dispose);
  });

  testWidgets('a slider hidden on its first frame does not export disconnected popup nodes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ObsidianTheme.build(),
        home: Scaffold(
          body: Opacity(
            opacity: 0,
            child: ObsidianSliderScope(child: Slider(value: 0.5, onChanged: (_) {})),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Windows slider updates stay connected from the first route transition frame', (tester) async {
    final navigator = GlobalKey<NavigatorState>();

    Widget page(String label) => Scaffold(
      body: Column(
        children: [
          Text(label),
          Slider(value: 0.5, onChanged: (_) {}),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, theme: ObsidianTheme.build(), home: page('Original')));
    await tester.pumpAndSettle();

    final route = MaterialPageRoute<void>(builder: (_) => page('Incoming'));

    navigator.currentState!.push<void>(route);
    await tester.pump();
    expect(route.animation!.value, 0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Incoming'), findsOneWidget);
    expect(find.bySemanticsLabel('Original'), findsNothing);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Original'), findsOneWidget);
    expect(find.bySemanticsLabel('Incoming'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('retained slider tabs keep connected updates through interrupted replacements', (tester) async {
    final tabKey = GlobalKey();

    Widget tab(String label) => Column(
      key: ValueKey(label),
      children: [
        Text(label),
        Slider(value: 0.5, onChanged: (_) {}),
      ],
    );

    var children = [tab('Original'), tab('Other')];

    Future<void> show(int index) => tester.pumpWidget(
      MaterialApp(
        theme: ObsidianTheme.build(),
        home: Scaffold(
          body: RetainedTabView(key: tabKey, index: index, children: children),
        ),
      ),
    );

    await show(0);
    await tester.pumpAndSettle();
    children = [tab('Replacement'), children[1]];
    await show(0);
    await tester.pump(const Duration(milliseconds: 30));
    await show(1);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Other'), findsOneWidget);
    expect(find.bySemanticsLabel('Replacement'), findsNothing);

    await show(0);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Replacement'), findsOneWidget);
    expect(find.bySemanticsLabel('Other'), findsNothing);
    expect(find.bySemanticsLabel('Original'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

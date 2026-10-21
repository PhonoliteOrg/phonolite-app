import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/navigation/app_bottom_navigation.dart';
import 'package:phonolite_app/ui/shell/navigation/app_side_navigation.dart';
import 'package:phonolite_app/ui/shell/toolbars/base_page_toolbar.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final width in [320.0, 1280.0]) {
    testWidgets('toolbar slots retain actions and a constrained title at $width', (tester) async {
      _setSize(tester, width);
      var backActions = 0;
      var editActions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Toolbar(onBack: () => backActions++, onEdit: () => editActions++),
          ),
        ),
      );
      final back = find.byTooltip('Go back');
      final edit = find.byTooltip('Edit collection');
      expect(tester.getRect(back).right, lessThan(tester.getRect(edit).left));
      await tester.tap(back);
      await tester.tap(edit);
      expect(backActions, 1);
      expect(editActions, 1);
      expect(find.byType(ObsidianNavIcon), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('title and back toolbars preserve their independent actions at $width', (tester) async {
      _setSize(tester, width);
      var backActions = 0;
      var titleActions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LibraryHeader(
                  title: 'COLLECTION',
                  trailing: IconButton(
                    tooltip: 'Collection action',
                    onPressed: () => titleActions++,
                    icon: const Icon(Icons.edit),
                  ),
                ),
                DetailActionHeader(
                  backLabel: 'Back to artist',
                  onBack: () => backActions++,
                  actions: const Wrap(children: [Text('Page actions')]),
                ),
                DetailActionHeader(backLabel: 'Disabled back', backEnabled: false, onBack: () => backActions++),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Collection action'));
      await tester.tap(find.text('BACK TO ARTIST'));
      await tester.tap(find.text('DISABLED BACK'), warnIfMissed: false);
      expect(titleActions, 1);
      expect(backActions, 1);
      expect(find.text('Page actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a page can use the toolbar contract in its fixed navbar slot', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FixedToolbarPage()));
    expect(find.text('Fixed title'), findsOneWidget);
    expect(find.text('Page content'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final side in [false, true]) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
      testWidgets('${side ? 'side' : 'bottom'} navigation selects destinations on $platform', (tester) async {
        _setSize(tester, 430);
        var selected = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Builder(
              builder: (context) => Scaffold(
                body: MediaQuery(
                  data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 20, bottom: 24)),
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      const destinations = [
                        NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
                        NavigationDestination(icon: Icon(Icons.favorite), label: 'Liked'),
                        NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
                      ];
                      final navigation = side
                          ? AppSideNavigation(
                              destinations: destinations,
                              selectedIndex: selected,
                              onDestinationSelected: (index) => setState(() => selected = index),
                            )
                          : AppBottomNavigation(
                              destinations: destinations,
                              selectedIndex: selected,
                              onDestinationSelected: (index) => setState(() => selected = index),
                            );
                      return Align(alignment: Alignment.bottomLeft, child: navigation);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.widgetList<ObsidianNavIcon>(find.byType(ObsidianNavIcon)).map((icon) => icon.isSelected), [
          false,
          true,
          false,
        ]);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.widgetList<ObsidianNavIcon>(find.byType(ObsidianNavIcon)).map((icon) => icon.isSelected), [
          false,
          false,
          true,
        ]);
        if (!side) {
          expect(tester.getSize(find.byType(AppBottomNavigation)).height, 88);
          expect(find.byType(ObsidianGlassSurface), platform == TargetPlatform.iOS ? findsOneWidget : findsNothing);
        }
        expect(find.byWidgetPredicate((widget) => widget is BasePageToolbar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _setSize(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Toolbar extends BasePageToolbar {
  const _Toolbar({required this.onBack, required this.onEdit});
  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  Widget leadingContent(BuildContext context, BoxConstraints constraints) =>
      IconButton(tooltip: 'Go back', onPressed: onBack, icon: const Icon(Icons.arrow_back));

  @override
  Widget titleContent(BuildContext context, BoxConstraints constraints) =>
      const Text('A collection title that needs room', maxLines: 1, overflow: TextOverflow.ellipsis);

  @override
  Widget trailingActions(BuildContext context, BoxConstraints constraints) =>
      IconButton(tooltip: 'Edit collection', onPressed: onEdit, icon: const Icon(Icons.edit));
}

class _FixedToolbarPage extends BaseStatelessPage {
  const _FixedToolbarPage();

  @override
  bool get usesScaffold => true;

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    navbar: const PageToolbar(title: Text('Fixed title')),
    body: const PageBody.box(child: Text('Page content')),
  );
}

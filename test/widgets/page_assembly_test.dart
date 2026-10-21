import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

const _toolbarKey = ValueKey('page-toolbar');
const _bodyKey = ValueKey('page-body');

void main() {
  for (final slivers in [false, true]) {
    final bodyKind = slivers ? 'sliver' : 'scroll';

    testWidgets('scrolling toolbar and $bodyKind content share one scroller', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(_AssemblyPage(controller: controller, slivers: slivers)),
      );
      final toolbarBefore = tester.getTopLeft(find.byKey(_toolbarKey));
      final bodyBefore = tester.getTopLeft(find.byKey(_bodyKey));
      expect(find.byType(Scrollable), findsOneWidget);

      controller.jumpTo(40);
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(_toolbarKey)).dy,
        closeTo(toolbarBefore.dy - 40, 0.01),
      );
      expect(
        tester.getTopLeft(find.byKey(_bodyKey)).dy,
        closeTo(bodyBefore.dy - 40, 0.01),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fixed toolbar stays above scrolling $bodyKind content', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          _AssemblyPage(
            controller: controller,
            slivers: slivers,
            placement: PageToolbarPlacement.fixed,
          ),
        ),
      );
      final toolbarBefore = tester.getRect(find.byKey(_toolbarKey));
      final bodyBefore = tester.getTopLeft(find.byKey(_bodyKey));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);

      controller.jumpTo(120);
      await tester.pump();

      expect(tester.getRect(find.byKey(_toolbarKey)), toolbarBefore);
      expect(
        tester.getTopLeft(find.byKey(_bodyKey)).dy,
        closeTo(bodyBefore.dy - 120, 0.01),
      );
      expect(tester.takeException(), isNull);
    });

    for (final placement in PageToolbarPlacement.values) {
      testWidgets(
        '$placement $bodyKind assembly applies playback clearances once',
        (tester) async {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          final page = _AssemblyPage(
            controller: controller,
            slivers: slivers,
            placement: placement,
          );
          await tester.pumpWidget(_host(page));
          final toolbarBefore = tester.getTopLeft(find.byKey(_toolbarKey));
          final extentBefore = controller.position.maxScrollExtent;

          await tester.pumpWidget(_host(page, top: 17, bottom: 43));

          expect(
            tester.getTopLeft(find.byKey(_toolbarKey)).dy - toolbarBefore.dy,
            closeTo(17, 0.01),
          );
          expect(
            controller.position.maxScrollExtent - extentBefore,
            closeTo(60, 0.01),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [360.0, 1280.0]) {
    testWidgets('fixed toolbar uses its actual responsive height at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          _AssemblyPage(
            controller: controller,
            placement: PageToolbarPlacement.fixed,
            responsiveToolbar: true,
          ),
        ),
      );

      final toolbar = tester.getRect(find.byKey(_toolbarKey));
      expect(toolbar.height, width < 500 ? 104 : 52);
      expect(tester.getTopLeft(find.byKey(_bodyKey)).dy, toolbar.bottom);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a fixed box body can use the remaining viewport for flex', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _FlexPage(), top: 17, bottom: 43));

    final toolbar = tester.getRect(find.byKey(_toolbarKey));
    expect(toolbar.top, 17);
    expect(tester.getTopLeft(find.text('First row')).dy, toolbar.bottom);
    expect(
      tester.getBottomLeft(find.text('Last row')).dy,
      tester.view.physicalSize.height / tester.view.devicePixelRatio - 43,
    );
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar and body are assembled inside the same reactive scope', (
    tester,
  ) async {
    final count = ValueNotifier(0);
    addTearDown(count.dispose);
    await tester.pumpWidget(_host(_ReactivePage(count)));
    expect(find.text('Toolbar 0'), findsOneWidget);
    expect(find.text('Body 0'), findsOneWidget);

    count.value = 1;
    await tester.pump();

    expect(find.text('Toolbar 1'), findsOneWidget);
    expect(find.text('Body 1'), findsOneWidget);
    expect(find.text('Toolbar 0'), findsNothing);
    expect(find.text('Body 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page without a toolbar still assembles content and insets', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _NoToolbarPage(), top: 17, bottom: 43));

    expect(tester.getTopLeft(find.byKey(_bodyKey)).dy, 17);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget page, {double top = 0, double bottom = 0}) => MaterialApp(
  home: Scaffold(
    body: PlaybackContentInset(top: top, bottom: bottom, child: page),
  ),
);

class _AssemblyPage extends BaseStatelessPage {
  const _AssemblyPage({
    required this.controller,
    this.slivers = false,
    this.placement = PageToolbarPlacement.scrolling,
    this.responsiveToolbar = false,
  });

  final ScrollController controller;
  final bool slivers;
  final PageToolbarPlacement placement;
  final bool responsiveToolbar;

  @override
  PageToolbarPlacement get toolbarPlacement => placement;

  @override
  EdgeInsetsGeometry get navbarPadding => EdgeInsets.zero;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    const content = SizedBox(
      key: _bodyKey,
      height: 1600,
      child: Text('Scrollable content'),
    );
    return assemble(
      context,
      navbar: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          key: _toolbarKey,
          height: responsiveToolbar && constraints.maxWidth < 500 ? 104 : 52,
          child: const Text('Page toolbar'),
        ),
      ),
      body: slivers
          ? PageBody.slivers(
              controller: controller,
              slivers: const [SliverToBoxAdapter(child: content)],
            )
          : PageBody.scroll(controller: controller, child: content),
    );
  }
}

class _FlexPage extends BaseStatelessPage {
  const _FlexPage();

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  EdgeInsetsGeometry get navbarPadding => EdgeInsets.zero;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    navbar: const SizedBox(
      key: _toolbarKey,
      height: 52,
      child: Text('Fixed toolbar'),
    ),
    body: const PageBody.box(
      includePlaybackInsets: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('First row'), Spacer(), Text('Last row')],
      ),
    ),
  );
}

class _ReactivePage extends BaseStatelessPage {
  const _ReactivePage(this.count);

  final ValueListenable<int> count;

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) =>
      ValueListenableBuilder<int>(
        valueListenable: count,
        builder: (context, value, child) => assemble(
          context,
          navbar: Text('Toolbar $value'),
          body: PageBody.box(child: Text('Body $value')),
        ),
      );
}

class _NoToolbarPage extends BaseStatelessPage {
  const _NoToolbarPage();

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    body: const PageBody.scroll(
      child: SizedBox(key: _bodyKey, height: 1200, child: Text('Only content')),
    ),
  );
}

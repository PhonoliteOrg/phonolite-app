import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/command_link_button.dart';
import 'package:phonolite_app/ui/shell/base_form_page.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/structures/modals/base_alert_modal.dart';
import 'package:phonolite_app/ui/structures/sections/base_section.dart';
import 'package:phonolite_app/ui/structures/sections/base_sliver_section.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('page hooks render navigation and own controller cleanup', (
    tester,
  ) async {
    final controller = _CounterController();
    await tester.pumpWidget(MaterialApp(home: _CounterPage(controller)));
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Count 0'), findsOneWidget);

    controller.increment();
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.disposals, 1);
    controller.increment();
    expect(controller.count, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an embedded page leaves the host scaffold in charge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _EmbeddedPage())),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Embedded content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('form layout respects keyboard and playback space at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var backActions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: const EdgeInsets.only(bottom: 180)),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: PlaybackContentInset(
                  top: 12,
                  bottom: 48,
                  child: _FormPage(onBack: () => backActions++),
                ),
              ),
            ),
          ),
        ),
      );
      final formSize = tester.getSize(find.byKey(const ValueKey('form-body')));
      expect(formSize.width, closeTo(width < 600 ? width - 40 : 560, 0.1));
      final toolbar = find.byType(DetailActionHeader);
      expect(tester.getTopLeft(toolbar).dy, 28);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('form-body'))).dy,
        closeTo(900 - 180 - 48 - 20, 0.1),
      );
      scrollable.position.jumpTo(0);
      await tester.pump();
      await tester.tap(find.text('BACK TO SETTINGS'));
      expect(backActions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('form dismissal guard also disables its back action', (
    tester,
  ) async {
    var backActions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _FormPage(allowPop: false, onBack: () => backActions++),
        ),
      ),
    );
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await tester.tap(find.byType(CommandLinkButton), warnIfMissed: false);
    expect(backActions, 0);
  });

  testWidgets('modal hooks update content and release bindings on dismissal', (
    tester,
  ) async {
    final controller = _CounterController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _CounterModal(controller),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Modal title'), findsOneWidget);
    expect(find.text('Count 0'), findsOneWidget);
    controller.increment();
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(controller.disposals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section implementations can customize their heading gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Section())),
    );
    final header = find.byKey(const ValueKey('section-heading'));
    final content = find.byKey(const ValueKey('section-content'));
    expect(tester.getTopLeft(content).dy - tester.getBottomLeft(header).dy, 24);
  });

  testWidgets('sliver sections support optional headings without overflow', (
    tester,
  ) async {
    for (final title in [null, 'Collection']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [_SliverSection(title)]),
          ),
        ),
      );
      expect(
        find.text('Collection'),
        title == null ? findsNothing : findsOneWidget,
      );
      expect(find.text('Row'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

class _CounterController extends FeatureController {
  int count = 0;
  int disposals = 0;

  void increment() => update(() => count++);

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _CounterPage extends BasePage {
  const _CounterPage(this.controller);
  final _CounterController controller;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends BasePageState<_CounterPage> {
  late final controller = bindController(widget.controller);

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.fixed;

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    navbar: const Text('Navigation'),
    body: PageBody.box(child: Text('Count ${controller.count}')),
  );
}

class _EmbeddedPage extends BaseStatelessPage {
  const _EmbeddedPage();

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    body: const PageBody.box(child: Text('Embedded content')),
  );
}

class _FormPage extends BasePage {
  const _FormPage({required this.onBack, this.allowPop = true});
  final VoidCallback onBack;
  final bool allowPop;

  @override
  State<_FormPage> createState() => _FormPageState();
}

class _FormPageState extends BaseFormPageState<_FormPage> {
  @override
  String pageTitle(BuildContext context) => 'FORM';

  @override
  bool? get canPopPage => widget.allowPop;

  @override
  bool get backButtonEnabled => widget.allowPop;

  @override
  void onBack(BuildContext context) => widget.onBack();

  @override
  Widget formContent(BuildContext context) => const SizedBox(
    key: ValueKey('form-body'),
    width: double.infinity,
    height: 1000,
    child: Text('Form fields'),
  );
}

class _CounterModal extends BaseAlertModal {
  const _CounterModal(this.controller);
  final _CounterController controller;

  @override
  State<_CounterModal> createState() => _CounterModalState();
}

class _CounterModalState extends BaseAlertModalState<_CounterModal> {
  late final controller = bindController(widget.controller);

  @override
  Widget modalTitle(BuildContext context) => const Text('Modal title');

  @override
  Widget modalContent(BuildContext context) =>
      Text('Count ${controller.count}');

  @override
  List<Widget> modalActions(BuildContext context) => [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Close'),
    ),
  ];
}

class _Section extends BaseSection {
  const _Section();

  @override
  String get sectionTitle => 'Section';

  @override
  double get headingSpacing => 24;

  @override
  Widget sectionHeader(BuildContext context) =>
      Text(sectionTitle, key: const ValueKey('section-heading'));

  @override
  List<Widget> sectionContent(BuildContext context) => [
    const Text('Content', key: ValueKey('section-content')),
  ];
}

class _SliverSection extends BaseSliverSection {
  const _SliverSection(this.sectionTitle);

  @override
  final String? sectionTitle;

  @override
  Widget sectionSliver(BuildContext context) =>
      const SliverToBoxAdapter(child: Text('Row'));
}

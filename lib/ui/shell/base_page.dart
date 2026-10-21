import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/shell/page_body.dart';

export 'package:phonolite_app/ui/shell/page_body.dart';

typedef PageAssembler = Widget Function(BuildContext context, {Widget? navbar, required PageBody body});

/// Shared page framing. Pages supply slots; this owner assembles their layout.
mixin PageStructure {
  @protected
  bool get usesScaffold => false;

  @protected
  bool get usesSafeArea => false;

  @protected
  Color? get pageBackgroundColor => null;

  @protected
  PageToolbarPlacement get toolbarPlacement => PageToolbarPlacement.scrolling;

  @protected
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 12);

  /// Reactive wrappers call [assemble] with both slots from the same snapshot.
  @protected
  Widget pageContent(BuildContext context, PageAssembler assemble);

  /// Adds a visual dismissal guard or other page-specific outer decoration.
  @protected
  Widget decoratePage(BuildContext context, Widget page) => page;

  Widget _assemblePage(BuildContext context) => pageContent(context, (context, {navbar, required body}) {
    Widget page = PageLayout(
      navbar: navbar,
      body: body,
      toolbarPlacement: toolbarPlacement,
      navbarPadding: navbarPadding,
    );

    if (usesSafeArea) {
      page = SafeArea(child: page);
    }

    if (usesScaffold) {
      page = Scaffold(backgroundColor: pageBackgroundColor, body: page);
    }

    return decoratePage(context, page);
  });
}

abstract class BasePage extends StatefulWidget {
  const BasePage({super.key});
}

/// Owns visual controller bindings; functional work stays in the controllers.
abstract class BasePageState<T extends BasePage> extends State<T> with ControllerBinding<T>, PageStructure {
  @override
  @nonVirtual
  Widget build(BuildContext context) => _assemblePage(context);
}

abstract class BaseStatelessPage extends StatelessWidget with PageStructure {
  const BaseStatelessPage({super.key});

  @override
  @nonVirtual
  Widget build(BuildContext context) => _assemblePage(context);
}

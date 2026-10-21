import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';

abstract class BaseAlertModal extends StatefulWidget {
  const BaseAlertModal({super.key});
}

/// Standard alert layout with independent title, content and action hooks.
abstract class BaseAlertModalState<T extends BaseAlertModal> extends State<T> with ControllerBinding<T> {
  @protected
  bool get modalScrollable => false;

  @protected
  Widget modalTitle(BuildContext context);

  @protected
  Widget modalContent(BuildContext context);

  @protected
  List<Widget> modalActions(BuildContext context);

  @override
  @nonVirtual
  Widget build(BuildContext context) => ObsidianModalScope(
    builder: (context) => ObsidianAlertDialog(
      scrollable: modalScrollable,
      title: modalTitle(context),
      content: modalContent(context),
      actions: modalActions(context),
    ),
  );
}

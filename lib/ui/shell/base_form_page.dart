import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';

/// Shared auth-form layout, keyboard handling and playback-aware spacing.
abstract class BaseFormPageState<T extends BasePage> extends BasePageState<T> {
  @protected
  String pageTitle(BuildContext context);

  @protected
  Widget formContent(BuildContext context);

  @protected
  bool showBackButton(BuildContext context) => true;

  @protected
  bool get backButtonEnabled => true;

  @protected
  String get backLabel => 'Back to settings';

  @protected
  bool? get canPopPage => null;

  @protected
  double get maxFormWidth => 560;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.only(bottom: 24);

  @protected
  void onBack(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget decoratePage(BuildContext context, Widget page) {
    final canPop = canPopPage;
    final dismissible = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: page,
    );

    return canPop == null ? dismissible : PopScope(canPop: canPop, child: dismissible);
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
    context,
    navbar: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBackButton(context)) ...[
          DetailActionHeader(backLabel: backLabel, backEnabled: backButtonEnabled, onBack: () => onBack(context)),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFormWidth),
            child: LibraryHeader(title: pageTitle(context), maxLines: 3),
          ),
        ),
      ],
    ),
    body: PageBody.scroll(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      includeKeyboardInset: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxFormWidth),
          child: ObsidianModalScope(builder: formContent),
        ),
      ),
    ),
  );
}

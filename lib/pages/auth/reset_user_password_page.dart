import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/auth/password_change_controller.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/base_form_page.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';

class ResetUserPasswordPage extends BasePage {
  static const String routeName = '/settings/user/password';

  final AppController controller;

  const ResetUserPasswordPage({super.key, required this.controller});

  static Route<void> route(AppController controller) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: routeName),
    builder: (_) => ResetUserPasswordPage(controller: controller),
  );

  @override
  State<ResetUserPasswordPage> createState() => _ResetUserPasswordPageState();
}

class _ResetUserPasswordPageState extends BaseFormPageState<ResetUserPasswordPage> {
  late final PasswordChangeController _feature = bindController(PasswordChangeController(widget.controller));
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  int _lastClearRevision = 0;

  @override
  bool get backButtonEnabled => !_feature.saving;

  @override
  bool? get canPopPage => !_feature.saving;

  @override
  void initState() {
    super.initState();

    _feature.addListener(_clearPasswordsAfterAction);
  }

  @override
  void dispose() {
    _feature.removeListener(_clearPasswordsAfterAction);
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();

    super.dispose();
  }

  @override
  String pageTitle(BuildContext context) => _feature.completed ? 'PASSWORD UPDATED' : 'RESET PASSWORD';

  @override
  void onBack(BuildContext context) => _goBack();

  Widget _passwordField(
    BuildContext context, {
    required Key key,
    required TextEditingController controller,
    required String label,
    String? autofillHint,
    bool submit = false,
  }) => ObsidianTextField(
    key: key,
    controller: controller,
    label: label,
    height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
    cut: 0,
    startPadding: 24,
    isDense: true,
    enabled: !_feature.saving,
    obscureText: true,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: submit ? TextInputAction.done : TextInputAction.next,
    autofillHints: autofillHint == null ? null : [autofillHint],
    onSubmitted: (_) => _handlePasswordSubmitted(context, submit: submit),
  );

  void _handlePasswordSubmitted(BuildContext context, {required bool submit}) {
    if (submit) {
      unawaited(_submit());
    } else {
      FocusScope.of(context).nextFocus();
    }
  }

  void _clearPasswordsAfterAction() {
    if (_feature.clearPasswordsRevision != _lastClearRevision) {
      _lastClearRevision = _feature.clearPasswordsRevision;
      _clearPasswords();
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    await _feature.submit(
      currentPassword: _currentPassword.text,
      newPassword: _newPassword.text,
      confirmation: _confirmation.text,
    );
  }

  void _goBack() {
    if (_feature.saving) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _clearPasswords();

    Navigator.of(context).pop();
  }

  void _clearPasswords() {
    _currentPassword.clear();
    _newPassword.clear();
    _confirmation.clear();
  }

  @override
  Widget formContent(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted);

    if (_feature.completed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your password has been updated. You are still signed in on this device.', style: bodyStyle),
          const SizedBox(height: 20),
          ObsidianModalActions(
            children: [ModalActionButton(label: 'Done', onPressed: _goBack)],
          ),
        ],
      );
    }

    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter your current password and choose a new one. Other devices will be signed out; this device stays connected.',
            style: bodyStyle,
          ),
          if (!_feature.sessionChanged) ...[
            const SizedBox(height: 24),
            _passwordField(
              context,
              key: const ValueKey('current-password'),
              controller: _currentPassword,
              label: 'Current password',
              autofillHint: AutofillHints.password,
            ),
            const SizedBox(height: 20),
            _passwordField(
              context,
              key: const ValueKey('new-password'),
              controller: _newPassword,
              label: 'New password',
              autofillHint: AutofillHints.newPassword,
            ),
            const SizedBox(height: 20),
            _passwordField(
              context,
              key: const ValueKey('confirm-new-password'),
              controller: _confirmation,
              label: 'Confirm new password',
              submit: true,
            ),
          ],
          if (_feature.error != null || _feature.sessionChanged) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: SelectableText(
                _feature.error ?? 'The connection or account changed. Return to settings and try again.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (!_feature.sessionChanged) ...[
            const SizedBox(height: 20),
            ObsidianModalActions(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Visibility(
                      visible: !_feature.saving,
                      maintainSize: true,
                      maintainState: true,
                      maintainAnimation: true,
                      child: ModalActionButton(label: 'Reset password', onPressed: _feature.saving ? null : _submit),
                    ),
                    if (_feature.saving)
                      const Positioned.fill(
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Resetting password'),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

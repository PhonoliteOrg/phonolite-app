import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/layouts/playback_content_inset.dart';

import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/server_connection.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/modals/modal_action_button.dart';
import '../widgets/modals/obsidian_dialog.dart';
import '../widgets/modals/obsidian_modal_scope.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/obsidian_theme.dart';

class ResetUserPasswordPage extends StatefulWidget {
  const ResetUserPasswordPage({super.key, required this.controller});

  static const routeName = '/settings/user/password';

  static Route<void> route(AppController controller) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: routeName),
    builder: (_) => ResetUserPasswordPage(controller: controller),
  );

  final AppController controller;

  @override
  State<ResetUserPasswordPage> createState() => _ResetUserPasswordPageState();
}

class _ResetUserPasswordPageState extends State<ResetUserPasswordPage> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  late final int _sessionRevision;
  late final StreamSubscription<AuthState> _authSubscription;
  bool _saving = false;
  bool _sessionChanged = false;
  bool _completed = false;
  String? _error;

  bool get _isCurrentSession =>
      widget.controller.authState.isAuthorized &&
      widget.controller.connection.sessionRevision == _sessionRevision;

  @override
  void initState() {
    super.initState();
    _sessionRevision = widget.controller.connection.sessionRevision;
    _sessionChanged = !_isCurrentSession;
    _authSubscription = widget.controller.authStream.listen((_) {
      if (!mounted || _saving || _completed || _isCurrentSession) return;
      _clearPasswords();
      setState(() => _sessionChanged = true);
    });
  }

  @override
  void dispose() {
    unawaited(_authSubscription.cancel());
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            16 + PlaybackContentInset.topOf(context),
            20,
            20 +
                PlaybackContentInset.bottomOf(context) +
                MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommandLinkButton(
                label: 'Back to settings',
                enabled: !_saving,
                onTap: _goBack,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LibraryHeader(
                        title: _completed
                            ? 'PASSWORD UPDATED'
                            : 'RESET PASSWORD',
                        moduleCount: 0,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      ObsidianModalScope(builder: _buildForm),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted);
    if (_completed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your password has been updated. You are still signed in on this device.',
            style: bodyStyle,
          ),
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
          if (!_sessionChanged) ...[
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
          if (_error != null || _sessionChanged) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: SelectableText(
                _error ??
                    'The connection or account changed. Return to settings and try again.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          if (!_sessionChanged) ...[
            const SizedBox(height: 20),
            ObsidianModalActions(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Visibility(
                      visible: !_saving,
                      maintainSize: true,
                      maintainState: true,
                      maintainAnimation: true,
                      child: ModalActionButton(
                        label: 'Reset password',
                        onPressed: _saving ? null : _submit,
                      ),
                    ),
                    if (_saving)
                      const Positioned.fill(
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Resetting password',
                            ),
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
    enabled: !_saving,
    obscureText: true,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: submit ? TextInputAction.done : TextInputAction.next,
    autofillHints: autofillHint == null ? null : [autofillHint],
    onSubmitted: (_) {
      if (submit) {
        unawaited(_submit());
      } else {
        FocusScope.of(context).nextFocus();
      }
    },
  );

  String? _validate() {
    if (_currentPassword.text.isEmpty) return 'Enter your current password.';
    if (utf8.encode(_currentPassword.text).length > 1024) {
      return 'Your current password is too long.';
    }
    if (_newPassword.text.isEmpty) {
      return 'Enter your new password.';
    }
    if (utf8.encode(_newPassword.text).length > 1024) {
      return 'Your new password is too long.';
    }
    if (_confirmation.text != _newPassword.text) {
      return 'The new passwords do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving || _completed) return;
    if (!_isCurrentSession) {
      _clearPasswords();
      setState(() => _sessionChanged = true);
      return;
    }
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.resetUserPassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      _clearPasswords();
      setState(() => _completed = true);
    } catch (error) {
      if (!mounted) return;
      _clearPasswords();
      setState(() {
        _error = error is PasswordChangeException
            ? error.message
            : 'The password change could not be confirmed. Check your connection and password before trying again.';
        _sessionChanged =
            !_isCurrentSession ||
            (error is PasswordChangeException && error.requiresSignIn);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goBack() {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _clearPasswords();
    Navigator.of(context).pop();
  }

  void _clearPasswords() {
    _currentPassword.clear();
    _newPassword.clear();
    _confirmation.clear();
  }
}

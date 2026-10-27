import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/account_sessions_controller.dart';
import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class AccountSessionsSetting extends StatefulWidget {
  final Future<int> Function() onSignOutOtherDevices;
  final Future<void> Function() onSignOutAllDevices;
  final bool Function() sessionIsCurrent;

  const AccountSessionsSetting({
    super.key,
    required this.onSignOutOtherDevices,
    required this.onSignOutAllDevices,
    required this.sessionIsCurrent,
  });

  @override
  State<AccountSessionsSetting> createState() => _AccountSessionsSettingState();
}

class _AccountSessionsSettingState extends State<AccountSessionsSetting>
    with ControllerBinding<AccountSessionsSetting> {
  late final AccountSessionsController _feature = bindController(AccountSessionsController());
  bool _confirming = false;

  bool get _busy => _confirming || _feature.busy;

  Future<void> _signOutOtherDevices() async {
    final action = widget.onSignOutOtherDevices;
    final sessionIsCurrent = widget.sessionIsCurrent;
    final confirmed = await _confirm(
      title: 'Sign out other devices?',
      message:
          'Sign out every other app session for this account? Streaming on those devices will stop and they will need to sign in again. This device and admin console sessions stay signed in.',
      confirmLabel: 'Sign out other devices',
      sessionIsCurrent: sessionIsCurrent,
    );

    if (confirmed && mounted) {
      await _feature.signOutOtherDevices(action, sessionIsCurrent: sessionIsCurrent);
    }
  }

  Future<void> _signOutAllDevices() async {
    final action = widget.onSignOutAllDevices;
    final sessionIsCurrent = widget.sessionIsCurrent;
    final confirmed = await _confirm(
      title: 'Sign out all devices?',
      message:
          'Sign out every app session for this account, including this device? Streaming will stop and all apps will need to sign in again. Admin console sessions stay signed in.',
      confirmLabel: 'Sign out all devices',
      sessionIsCurrent: sessionIsCurrent,
    );

    if (confirmed && mounted) {
      await _feature.signOutAllDevices(action, sessionIsCurrent: sessionIsCurrent);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required bool Function() sessionIsCurrent,
  }) async {
    if (_busy || !sessionIsCurrent()) {
      return false;
    }

    setState(() => _confirming = true);

    try {
      final confirmed = await ConfirmationModal.show(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      );

      return confirmed && mounted && sessionIsCurrent();
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  Widget _feedback(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          _feature.message!,
          key: const ValueKey('account-session-feedback'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _feature.failed ? Theme.of(context).colorScheme.error : ObsidianPalette.textMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('sign-out-other-devices'),
          child: buildSettingsRow(
            context,
            leading: const Icon(PhonoliteIcons.logOut),
            title: 'Sign out other devices',
            subtitle: 'Keep this device signed in and stop other app sessions.',
            trailing: const Icon(PhonoliteIcons.chevronRight),
            onTap: _busy ? null : _signOutOtherDevices,
          ),
        ),
        const SettingsDivider(),
        KeyedSubtree(
          key: const ValueKey('sign-out-all-devices'),
          child: buildSettingsRow(
            context,
            leading: Icon(PhonoliteIcons.logOut, color: Theme.of(context).colorScheme.error),
            title: 'Sign out all devices',
            subtitle: 'Admin console sessions stay signed in.',
            trailing: const Icon(PhonoliteIcons.chevronRight),
            titleColor: Theme.of(context).colorScheme.error,
            onTap: _busy ? null : _signOutAllDevices,
          ),
        ),
        if (_feature.busy) const LinearProgressIndicator(key: ValueKey('account-session-progress'), minHeight: 2),
        if (_feature.message != null) _feedback(context),
      ],
    );
  }
}

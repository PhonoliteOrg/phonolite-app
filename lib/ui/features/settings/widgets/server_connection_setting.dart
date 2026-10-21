import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/ui/features/settings/widgets/settings_row.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';

String settingsLoginActionLabel(SessionStatus status) {
  return switch (status) {
    SessionStatus.authenticated => 'Change server',
    SessionStatus.serverUnavailable => 'Change server',
    SessionStatus.serverReachable => 'Log in',
    SessionStatus.checking => 'Checking',
    SessionStatus.offline => 'Connect / Log in',
  };
}

Widget settingsServerActions(
  BuildContext context, {
  required AppController controller,
  required AuthState authState,
  required VoidCallback onLogin,
}) {
  final enabled = authState.status != SessionStatus.checking;
  final loginAction = enabled ? onLogin : null;
  final canRetry = authState.status == SessionStatus.serverUnavailable;
  final retryAction = canRetry && !authState.isReconnecting ? () async => controller.retryServerConnection() : null;
  final retryLabel = authState.isReconnecting ? 'Reconnecting...' : 'Retry';
  final IconData loginIcon;

  if (authState.status == SessionStatus.checking) {
    loginIcon = PhonoliteIcons.hourglass;
  } else {
    loginIcon = authState.hasSession ? PhonoliteIcons.arrowLeftRight : PhonoliteIcons.logIn;
  }

  if (isCompactListWidth(context)) {
    if (authState.hasSession) {
      return ObsidianOverflowActionButton(
        tooltip: 'Server actions',
        actions: [
          if (canRetry) ObsidianMenuAction(label: retryLabel, iconWidget: const ReloadIcon(), onTap: retryAction),
          ObsidianMenuAction(label: 'Change server', icon: PhonoliteIcons.arrowLeftRight, onTap: loginAction),
          ObsidianMenuAction(
            label: 'Disconnect',
            icon: PhonoliteIcons.logOut,
            variant: TechButtonVariant.danger,
            onTap: () async => controller.logout(),
          ),
        ],
      );
    }

    return SettingsIconAction(
      tooltip: settingsLoginActionLabel(authState.status),
      icon: loginIcon,
      onPressed: loginAction,
    );
  }

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (canRetry)
        TechButton(
          label: retryLabel,
          iconWidget: const ReloadIcon(),
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: retryAction,
        ),
      TechButton(
        label: settingsLoginActionLabel(authState.status),
        icon: loginIcon,
        density: TechButtonDensity.compact,
        chrome: TechButtonChrome.borderless,
        onTap: loginAction,
      ),
      if (authState.hasSession)
        TechButton(
          label: 'Disconnect',
          icon: PhonoliteIcons.logOut,
          variant: TechButtonVariant.danger,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: () async => controller.logout(),
        ),
    ],
  );
}

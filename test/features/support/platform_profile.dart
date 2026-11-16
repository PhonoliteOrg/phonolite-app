import 'package:flutter/material.dart';

/// How the shell presents playback on a platform's default window or screen.
enum PlayerSurface {
  /// A mini bar above bottom navigation that expands into a dismissible sheet.
  expandableSheet,

  /// A playback bar docked beside side navigation with every control visible.
  dockedBar,
}

/// The primary way people operate the app on a platform.
enum PrimaryInput { touch, pointerAndKeyboard }

/// How people return to the previous screen without a visible Back control.
enum BackNavigation {
  /// The platform back button or gesture (Android).
  systemBack,

  /// A drag from the leading screen edge (iOS).
  edgeSwipe,

  /// The mouse side Back button (desktop).
  mouseBackButton,
}

/// Product behavior a feature scenario may require. A profile lists what the
/// app is expected to offer on that platform; scenarios that need a missing
/// capability are reported as not applicable instead of passing silently.
enum Capability {
  /// Space toggles playback from anywhere outside text fields and controls.
  keyboardPlayPause,

  /// Escape dismisses dialogs.
  keyboardDismiss,

  /// The mouse side Forward button reopens the screen Back just left.
  mouseForward,

  /// Settings offers launch-at-startup and run-in-background.
  desktopLifecycle,

  /// The app installs its own updates and shows them in Settings.
  selfUpdate,

  /// The system manages storage locations; people cannot choose folders.
  managedStorage,
}

/// Everything platform-specific a feature scenario can observe, as data.
/// Adding a platform means adding a profile here, not writing new scenarios.
@immutable
class PlatformProfile {
  final String name;
  final TargetPlatform target;

  /// Logical window or screen size the scenarios run at.
  final Size screen;
  final double devicePixelRatio;
  final PlayerSurface playerSurface;
  final PrimaryInput input;
  final BackNavigation back;
  final Set<Capability> capabilities;

  const PlatformProfile({
    required this.name,
    required this.target,
    required this.screen,
    required this.devicePixelRatio,
    required this.playerSurface,
    required this.input,
    required this.back,
    this.capabilities = const {},
  });

  bool supports(Capability capability) => capabilities.contains(capability);

  @override
  String toString() => name;
}

const iosPhone = PlatformProfile(
  name: 'ios',
  target: TargetPlatform.iOS,
  screen: Size(393, 852),
  devicePixelRatio: 3,
  playerSurface: PlayerSurface.expandableSheet,
  input: PrimaryInput.touch,
  back: BackNavigation.edgeSwipe,
  capabilities: {Capability.managedStorage},
);

const androidPhone = PlatformProfile(
  name: 'android',
  target: TargetPlatform.android,
  screen: Size(412, 915),
  devicePixelRatio: 2.625,
  playerSurface: PlayerSurface.expandableSheet,
  input: PrimaryInput.touch,
  back: BackNavigation.systemBack,
);

const _desktopCapabilities = {
  Capability.keyboardPlayPause,
  Capability.keyboardDismiss,
  Capability.mouseForward,
  Capability.desktopLifecycle,
};

const macosDesktop = PlatformProfile(
  name: 'macos',
  target: TargetPlatform.macOS,
  screen: Size(1440, 900),
  devicePixelRatio: 2,
  playerSurface: PlayerSurface.dockedBar,
  input: PrimaryInput.pointerAndKeyboard,
  back: BackNavigation.mouseBackButton,
  capabilities: _desktopCapabilities,
);

const windowsDesktop = PlatformProfile(
  name: 'windows',
  target: TargetPlatform.windows,
  screen: Size(1440, 900),
  devicePixelRatio: 1.25,
  playerSurface: PlayerSurface.dockedBar,
  input: PrimaryInput.pointerAndKeyboard,
  back: BackNavigation.mouseBackButton,
  capabilities: {..._desktopCapabilities, Capability.selfUpdate},
);

const linuxDesktop = PlatformProfile(
  name: 'linux',
  target: TargetPlatform.linux,
  screen: Size(1280, 800),
  devicePixelRatio: 1,
  playerSurface: PlayerSurface.dockedBar,
  input: PrimaryInput.pointerAndKeyboard,
  back: BackNavigation.mouseBackButton,
  capabilities: {..._desktopCapabilities, Capability.selfUpdate},
);

const allPlatformProfiles = [iosPhone, androidPhone, macosDesktop, windowsDesktop, linuxDesktop];

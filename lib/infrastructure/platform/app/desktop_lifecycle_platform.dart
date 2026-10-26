import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/platform/app/linux_startup_registration.dart';

bool get desktopLifecycleSupported =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };

abstract interface class DesktopLifecyclePlatform {
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit});
  Future<void> setLaunchAtStartup(bool enabled);
  Future<void> setBackgroundEnabled(bool enabled);
  Future<void> hide();
  Future<void> show();
  Future<void> quit();
  Future<void> dispose();
}

/// Owns desktop plugin listeners and the tray; application policy stays in the controller.
class NativeDesktopLifecyclePlatform with WindowListener, TrayListener implements DesktopLifecyclePlatform {
  final WindowManager _window;
  final TrayManager _tray;
  Future<void> Function()? _onClose;
  Future<void> Function()? _onQuit;
  bool _trayReady = false;

  NativeDesktopLifecyclePlatform({WindowManager? window, TrayManager? tray})
    : _window = window ?? windowManager,
      _tray = tray ?? trayManager;

  @override
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit}) async {
    await _window.ensureInitialized();

    _onClose = onClose;
    _onQuit = onQuit;
    _window.addListener(this);
    _tray.addListener(this);

    // Intercept both modes so an explicit close can flush storage before exiting.
    await _window.setPreventClose(true);

    launchAtStartup.setup(
      appName: 'Phonolite',
      appPath: Platform.isWindows ? '"${Platform.resolvedExecutable}"' : Platform.resolvedExecutable,
    );
  }

  @override
  Future<void> dispose() async {
    _window.removeListener(this);
    _tray.removeListener(this);
    _onClose = null;
    _onQuit = null;

    if (_trayReady) {
      await _tray.destroy();
      _trayReady = false;
    }

    await _window.setPreventClose(false);
  }

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    if (Platform.isLinux) {
      await LinuxStartupRegistration().setEnabled(enabled);

      return;
    }

    final succeeded = enabled ? await launchAtStartup.enable() : await launchAtStartup.disable();

    if (!succeeded || await launchAtStartup.isEnabled() != enabled) {
      throw StateError('Could not change launch at login. Check your operating system’s login/startup settings.');
    }
  }

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {
    if (enabled && !_trayReady) {
      try {
        await _tray.setIcon(
          Platform.isWindows ? 'assets/images/phonolite-tray.ico' : 'assets/images/phonolite-logo-nobackground.png',
        );
        await _tray.setContextMenu(
          Menu(
            items: [
              MenuItem(key: 'show', label: 'Show Phonolite'),
              MenuItem.separator(),
              MenuItem(key: 'quit', label: 'Quit Phonolite'),
            ],
          ),
        );

        if (!Platform.isLinux) {
          await _tray.setToolTip('Phonolite');
        }

        _trayReady = true;
      } catch (_) {
        await _tray.destroy();
        rethrow;
      }
    } else if (!enabled && _trayReady) {
      // Keep the window reachable when disabling background mode while hidden.
      await show();
      await _tray.destroy();
      _trayReady = false;
    }
  }

  @override
  Future<void> hide() => _window.hide();

  @override
  Future<void> show() async {
    // WindowManager.show also restores a minimized window.
    await _window.show();
    await _window.focus();
  }

  @override
  Future<void> quit() => _window.destroy();

  void _dispatch(Future<void> Function()? action) {
    if (action != null) {
      unawaited(
        Future<void>.sync(action).catchError((Object error) {
          AppLogger.warning('Desktop action failed: $error');
        }),
      );
    }
  }

  @override
  void onWindowClose() => _dispatch(_onClose);

  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      _dispatch(show);
    } else {
      _dispatch(_tray.popUpContextMenu);
    }
  }

  @override
  void onTrayIconRightMouseDown() => _dispatch(_tray.popUpContextMenu);

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      _dispatch(show);
    } else if (menuItem.key == 'quit') {
      _dispatch(_onQuit);
    }
  }
}

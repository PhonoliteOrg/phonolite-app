import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'package:phonolite_app/data/configuration/app/desktop_window_configuration.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_tray.dart';
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
class NativeDesktopLifecyclePlatform with WindowListener implements DesktopLifecyclePlatform {
  static const _windowConstraints = MethodChannel('phonolite/window');

  final WindowManager _window;
  final DesktopTray _tray;
  Future<void> Function()? _onClose;
  Future<void> Function()? _onQuit;
  bool _trayReady = false;

  NativeDesktopLifecyclePlatform({WindowManager? window, DesktopTray? tray})
    : _window = window ?? windowManager,
      _tray = tray ?? NativeDesktopTray();

  @override
  Future<void> initialize({required Future<void> Function() onClose, required Future<void> Function() onQuit}) async {
    await _window.ensureInitialized();
    await _configureMinimumSize();

    _onClose = onClose;
    _onQuit = onQuit;
    _window.addListener(this);

    // Intercept both modes so an explicit close can flush storage before exiting.
    await _window.setPreventClose(true);

    launchAtStartup.setup(
      appName: 'Phonolite',
      appPath: Platform.isWindows ? '"${Platform.resolvedExecutable}"' : Platform.resolvedExecutable,
    );
  }

  Future<void> _configureMinimumSize() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // GTK must own the content minimum so header bars, borders and later
      // geometry updates retain the same usable area as the desktop layout.
      await _windowConstraints.invokeMethod<void>('setMinimumContentSize', {
        'width': DesktopWindowConfiguration.minimumWidth,
        'height': DesktopWindowConfiguration.minimumHeight,
      });

      return;
    }

    final windowSize = await _window.getSize();
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final contentSize = view == null ? windowSize : view.physicalSize / view.devicePixelRatio;

    // The plugin sizes native frames on Windows/macOS. Include decorations so
    // the Flutter content still reaches the desktop layout's minimum width.
    final minimumSize = Size(
      DesktopWindowConfiguration.minimumWidth + math.max(0.0, windowSize.width - contentSize.width).ceilToDouble(),
      DesktopWindowConfiguration.minimumHeight + math.max(0.0, windowSize.height - contentSize.height).ceilToDouble(),
    );
    await _window.setMinimumSize(minimumSize);

    final clampedSize = Size(
      math.max(windowSize.width, minimumSize.width),
      math.max(windowSize.height, minimumSize.height),
    );
    if (clampedSize != windowSize) {
      await _window.setSize(clampedSize);
    }
  }

  @override
  Future<void> dispose() async {
    _window.removeListener(this);
    _onClose = null;
    _onQuit = null;

    if (_trayReady) {
      _tray.dispose();
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
        _tray.show(onShow: () => _dispatch(show), onQuit: () => _dispatch(_onQuit));

        _trayReady = true;
      } catch (_) {
        _tray.dispose();
        rethrow;
      }
    } else if (!enabled && _trayReady) {
      // Keep the window reachable when disabling background mode while hidden.
      await show();
      _tray.dispose();
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
}

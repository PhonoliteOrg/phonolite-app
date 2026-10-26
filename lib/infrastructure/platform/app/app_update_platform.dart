import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';

abstract interface class AppUpdatePlatform {
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall});
  Future<void> showUpdate();
  Future<void> dispose();
}

class WindowsAppUpdatePlatform implements AppUpdatePlatform {
  final MethodChannel _channel;
  Future<void> Function()? _onInstall;

  WindowsAppUpdatePlatform({MethodChannel channel = const MethodChannel('phonolite/updates')}) : _channel = channel;

  @override
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall}) async {
    _onInstall = onInstall;
    _channel.setMethodCallHandler(_handleCall);

    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>('initialize');

      return AppUpdateConfiguration.fromPlatform(values ?? const {});
    } catch (_) {
      _channel.setMethodCallHandler(null);
      _onInstall = null;
      rethrow;
    }
  }

  @override
  Future<void> showUpdate() => _channel.invokeMethod<void>('showUpdate');

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    _onInstall = null;
    await _channel.invokeMethod<void>('dispose');
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'shutdownForUpdate') {
      await _onInstall?.call();
    }
  }
}

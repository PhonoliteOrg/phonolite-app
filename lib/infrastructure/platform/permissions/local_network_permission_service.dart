import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LocalNetworkPermissionService {
  final MethodChannel _channel;

  LocalNetworkPermissionService({MethodChannel channel = const MethodChannel('phonolite/permissions')})
    : _channel = channel;

  bool get isSupported {
    if (kIsWeb) {
      return false;
    }

    if (Platform.isIOS) {
      return true;
    }

    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  void dispose() => _channel.setMethodCallHandler(null);

  void setStatusHandler(void Function(String status) handler) {
    Future<void> handlePermissionStatus(MethodCall call) async {
      if (call.method != 'localNetworkPermission') {
        return;
      }

      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});

      handler(args['status']?.toString().toLowerCase().trim() ?? '');
    }

    _channel.setMethodCallHandler(handlePermissionStatus);
  }

  Future<void> refreshPermission() async {
    await _channel.invokeMethod('refreshLocalNetworkPermission');
  }

  Future<String> getPermission() async {
    final result = await _channel.invokeMethod('getLocalNetworkPermission');

    return result?.toString().toLowerCase().trim() ?? '';
  }

  Future<void> openAppSettings() async {
    await _channel.invokeMethod('openAppSettings');
  }
}

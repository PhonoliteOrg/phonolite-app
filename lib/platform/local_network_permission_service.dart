import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LocalNetworkPermissionService {
  LocalNetworkPermissionService({
    MethodChannel channel = const MethodChannel('phonolite/permissions'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    if (Platform.isIOS) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  void setStatusHandler(void Function(String status) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'localNetworkPermission') {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      handler(args['status']?.toString().toLowerCase().trim() ?? '');
    });
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

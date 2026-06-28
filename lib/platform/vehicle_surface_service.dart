import 'dart:io';

import 'package:flutter/services.dart';

class VehicleSurfaceService {
  VehicleSurfaceService({
    MethodChannel channel = const MethodChannel('phonolite/carplay'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  void setMethodHandler(
    Future<dynamic> Function(String method, Map<String, dynamic> arguments)
    handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      return handler(call.method, args);
    });
  }

  Future<void> notifyState(Map<String, dynamic> payload) async {
    await _channel.invokeMethod('carPlayState', payload);
  }

  Future<void> notifyAuthorization(bool authorized) async {
    await _channel.invokeMethod('authState', {'authorized': authorized});
  }
}

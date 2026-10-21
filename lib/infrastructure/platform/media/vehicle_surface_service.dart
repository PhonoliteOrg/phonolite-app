import 'dart:io';

import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/playback/vehicle_request.dart';
import 'package:phonolite_app/data/models/playback/vehicle_response.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_codec.dart';

class VehicleSurfaceService {
  final MethodChannel _channel;

  VehicleSurfaceService({MethodChannel channel = const MethodChannel('phonolite/carplay')}) : _channel = channel;

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  void dispose() => _channel.setMethodCallHandler(null);

  void setRequestHandler(Future<VehicleResponse?> Function(VehicleRequest request) handler) {
    Future<Object?> handleRequest(String method, Map<String, dynamic> arguments) async {
      final request = VehicleSurfaceCodec.decodeRequest(method, arguments);
      final response = await handler(request);

      return response == null ? null : VehicleSurfaceCodec.encodeResponse(response);
    }

    setMethodHandler(handleRequest);
  }

  void setMethodHandler(Future<dynamic> Function(String method, Map<String, dynamic> arguments) handler) {
    Future<dynamic> handleMethod(MethodCall call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});

      return handler(call.method, args);
    }

    _channel.setMethodCallHandler(handleMethod);
  }

  Future<void> notifyState(Map<String, dynamic> payload) async {
    await _channel.invokeMethod('carPlayState', payload);
  }

  Future<void> notifySourceState(VehicleSourceState state) => notifyState(VehicleSurfaceCodec.encodeResponse(state));

  Future<void> notifyAuthorization(bool authorized) async {
    await _channel.invokeMethod('authState', {'authorized': authorized});
  }
}

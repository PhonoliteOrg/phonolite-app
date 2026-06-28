import 'dart:io';

import 'package:flutter/services.dart';

class NativeRemoteCommand {
  const NativeRemoteCommand({required this.type, required this.arguments});

  final String type;
  final Map<String, dynamic> arguments;
}

class NowPlayingPlatformService {
  NowPlayingPlatformService({
    MethodChannel channel = const MethodChannel('phonolite/now_playing'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  void setRemoteCommandHandler(
    Future<void> Function(NativeRemoteCommand command) handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'remoteCommand') {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      await handler(
        NativeRemoteCommand(
          type: args['type']?.toString() ?? '',
          arguments: args,
        ),
      );
    });
  }

  Future<void> setNowPlaying(Map<String, dynamic> payload) async {
    await _channel.invokeMethod('setNowPlaying', payload);
  }

  Future<void> clearNowPlaying() async {
    await _channel.invokeMethod('clearNowPlaying');
  }
}

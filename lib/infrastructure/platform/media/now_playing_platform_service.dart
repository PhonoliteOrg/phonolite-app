import 'dart:io';

import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/data/models/playback/native_remote_command.dart';
import 'package:phonolite_app/infrastructure/platform/media/now_playing_codec.dart';

export 'package:phonolite_app/data/models/playback/native_remote_command.dart';

class NowPlayingPlatformService {
  final MethodChannel _channel;

  NowPlayingPlatformService({MethodChannel channel = const MethodChannel('phonolite/now_playing')})
    : _channel = channel;

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  // iOS can fetch and decode covers while Flutter's renderer is suspended.
  bool get loadsArtworkNatively => Platform.isIOS;

  void dispose() => _channel.setMethodCallHandler(null);

  void setRemoteCommandHandler(Future<void> Function(NativeRemoteCommand command) handler) {
    Future<void> handleRemoteCommand(MethodCall call) async {
      if (call.method != 'remoteCommand') {
        return;
      }

      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});

      await handler(NowPlayingCodec.decodeCommand(args));
    }

    _channel.setMethodCallHandler(handleRemoteCommand);
  }

  Future<void> setNowPlaying(Map<String, dynamic> payload) async {
    await _channel.invokeMethod('setNowPlaying', payload);
  }

  Future<void> publish(NativeNowPlayingSnapshot snapshot) => setNowPlaying(NowPlayingCodec.encodeSnapshot(snapshot));

  Future<void> clearNowPlaying() async {
    await _channel.invokeMethod('clearNowPlaying');
  }
}

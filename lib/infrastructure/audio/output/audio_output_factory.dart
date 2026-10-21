import 'dart:io';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/android_channel_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_output.dart';

/// Constructs an unopened adapter. The owning session awaits its initialization.
AudioPcmOutput createAudioPcmOutput({required int sampleRate, required int channels, required int deviceId}) {
  final AudioPcmOutput output;

  if (Platform.isWindows) {
    output = WaveOutPlayer(sampleRate: sampleRate, channels: channels, deviceId: deviceId);
  } else if (Platform.isMacOS || Platform.isIOS) {
    output = CoreAudioPlayer(sampleRate: sampleRate, channels: channels, deviceId: deviceId);
  } else if (Platform.isAndroid) {
    output = AndroidChannelPlayer(sampleRate: sampleRate, channels: channels, deviceId: deviceId);
  } else {
    throw Exception('Audio playback is only implemented for Windows, Apple platforms, and Android right now.');
  }

  return output;
}

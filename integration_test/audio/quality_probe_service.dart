import 'dart:convert';
import 'dart:developer' as developer;

import 'audio_probe.dart';
import 'quality_wire_probe.dart';

/// Only the test entry point registers this. It permits diagnostic repeats
/// against the current fixture without an AOT rebuild or production hooks.
void registerQualityProbe(AudioProbe probe) {
  developer.registerExtension('ext.phonolite.inspectQuality', (
    _,
    parameters,
  ) async {
    final quality = parameters['quality'] ?? 'high';
    if (!qualityTargets.containsKey(quality) || probe.lastRequest == null) {
      return developer.ServiceExtensionResponse.error(
        -32000,
        'No valid quality/fixture',
      );
    }
    try {
      final result = await inspectQualityWire(
        probe.lastRequest!,
        quality,
        sampleMs: (int.tryParse(parameters['sample_ms'] ?? '') ?? 2000).clamp(
          100,
          12000,
        ),
        timeoutMs: (int.tryParse(parameters['timeout_ms'] ?? '') ?? 10000)
            .clamp(500, 20000),
        sendPlaybackReport: parameters['send_playback'] == 'true',
      );
      return developer.ServiceExtensionResponse.result(jsonEncode(result));
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
        -32000,
        'Quality probe failed; inspect the test output',
      );
    }
  });
}

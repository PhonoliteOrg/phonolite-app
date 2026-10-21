import 'dart:isolate';
import 'dart:typed_data';

import 'package:phonolite_app/infrastructure/audio/protocol/raw_opus_stream_reader.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import 'observed_audio_engine.dart';

const qualityTargets = {'high': 160000, 'medium': 96000, 'low': 48000};

/// An independent request through the same production native transport. The
/// test runs it after stopping playback; no second audio output is opened.
Future<Map<String, Object?>> inspectQualityWire(
  StreamRequest request,
  String quality, {
  int sampleMs = 2000,
  int timeoutMs = 10000,
  bool sendPlaybackReport = false,
}) {
  final uri = Uri.parse(request.connection.baseUrl);
  final config = <String, Object?>{
    'host': uri.host == 'localhost' ? '127.0.0.1' : uri.host,
    'port':
        request.quicPort ??
        (uri.hasPort
                ? uri.port
                : uri.scheme == 'https'
                ? 443
                : 80) +
            1,
    'token': request.connection.token ?? '',
    'pin': request.connection.trust?.spki ?? '',
    'track_id': request.track.id,
    'quality': quality,
    'sample_ms': sampleMs,
    'timeout_ms': timeoutMs,
    'send_playback': sendPlaybackReport,
  };
  return _inspectConfig(config);
}

Future<Map<String, Object?>> _inspectConfig(Map<String, Object?> config) =>
    Isolate.run(() => _readQuality(config));

Future<Map<String, Object?>> _readQuality(Map<String, Object?> config) async {
  final client = QuicClient.connect(
    host: config['host'] as String,
    port: config['port'] as int,
    token: config['token'] as String,
    serverPin: config['pin'] as String,
  );
  final reader = RawOpusStreamReader();
  final buffer = Uint8List(65536);
  final clock = Stopwatch()..start();
  Map<String, Object?>? header;
  var packets = 0;
  var bytes = 0;
  var mediaMs = 0;
  var transportBytes = 0;
  var lastBufferReport = -1000;
  int? rangeEnd;
  var nextSeekId = 0;
  final announcements = <Map<String, Object?>>[];
  String? failure;
  final targetMs = config['sample_ms'] as int;
  try {
    client.openTrack(
      trackId: config['track_id'] as String,
      mode: 'fixed',
      quality: config['quality'] as String,
      frameMs: 20,
      startMs: 10000,
    );
    client.sendBufferStats(bufferMs: 0, targetMs: 10000, force: true);
    while (mediaMs < targetMs) {
      if (clock.elapsedMilliseconds > (config['timeout_ms'] as int)) {
        failure = header == null
            ? 'timeout_before_header'
            : 'timeout_after_partial_media';
        break;
      }
      if (clock.elapsedMilliseconds - lastBufferReport >= 500) {
        client.sendBufferStats(bufferMs: 0, targetMs: 10000, force: true);
        lastBufferReport = clock.elapsedMilliseconds;
        if (config['send_playback'] == true) {
          client.sendPlayback(
            trackId: config['track_id'] as String,
            positionMs: 10000,
            playing: true,
          );
        }
      }
      while (true) {
        final event = client.pollEvent();
        if (event == null) break;
        if (event['type'] == 'error') {
          throw StateError('Server rejected quality sample');
        }
        if (event['type'] == 'stream') {
          rangeEnd = (event['range_end_ms'] as num?)?.toInt();
          announcements.add({
            for (final key in [
              'position_ms',
              'range_end_ms',
              'end_of_track',
              'frame_ms',
            ])
              key: event[key],
          });
        }
      }
      final count = client.read(buffer);
      // The native client uses -5 for WouldBlock, matching the real engine's
      // receive loop. It is a pending read, not a transport failure.
      if (count == -5) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      if (count <= 0) throw StateError('Quality stream transport failed');
      transportBytes += count;
      for (final event in reader.add(Uint8List.sublistView(buffer, 0, count))) {
        if (event is RawOpusStreamHeader) {
          final h = event.header;
          header = {
            'bitrate_bps': h.bitrateBps,
            'sample_rate': h.sampleRate,
            'channels': h.channels,
            'frame_ms': h.frameMs,
          };
        } else if (event is RawOpusPacket && mediaMs < targetMs) {
          if (header == null) {
            throw StateError('Packet arrived without a header');
          }
          packets++;
          bytes += event.bytes.length;
          mediaMs += header['frame_ms'] as int;
        } else if (event is RawOpusEnd && mediaMs < targetMs) {
          client.seek(
            trackId: config['track_id'] as String,
            positionMs: rangeEnd ?? 10000 + mediaMs,
            seekId: ++nextSeekId,
          );
        }
      }
    }
    return {
      'requested_quality': config['quality'],
      'expected_target_bps': qualityTargets[config['quality']],
      'header': header,
      'packet_count': packets,
      'payload_bytes': bytes,
      'transport_bytes': transportBytes,
      'complete': mediaMs >= targetMs,
      'failure': failure,
      'announcements': announcements,
      'encoded_media_ms': mediaMs,
      'encoded_payload_kbps': mediaMs == 0 ? null : bytes * 8 / mediaMs,
      'request_start_ms': 10000,
      'elapsed_ms': clock.elapsedMilliseconds,
      'same_connection_as_playback': false,
    };
  } finally {
    client.close();
  }
}

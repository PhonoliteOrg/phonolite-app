part of 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

void _audioWorkerMain(AudioWorkerInit init) {
  final token = init.rootIsolateToken;

  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final receivePort = ReceivePort();

  IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
  IsolateNameServer.registerPortWithName(receivePort.sendPort, _audioWorkerPortName);

  init.sendPort.send(receivePort.sendPort);

  final engine = _AudioWorkerEngine(send: init.sendPort.send);

  Future<void> handleCommand(Object? message) async {
    if (message is! Map) {
      return;
    }

    final cmd = message['cmd'];

    switch (cmd) {
      case 'listening_context':
        final context = message['context'];

        engine.configureListening(
          context is Map ? Map<String, dynamic>.from(context) : null,
          discardPending: message['discard_pending'] != false,
        );
        break;
      case 'play':
        final rawQueue = message['queue'];
        final queue = rawQueue is List ? rawQueue.map((item) => item.toString()).toList() : const <String>[];
        final playbackId = (message['playback_id'] as num?)?.toInt() ?? 0;

        if (playbackId <= 0) {
          break;
        }

        final context = message['listening_context'];

        await engine.playTrack(
          playbackId: playbackId,
          trackId: message['track_id']?.toString() ?? '',
          trackTitle: message['track_title']?.toString() ?? '',
          baseUrl: message['base_url']?.toString() ?? '',
          token: message['token']?.toString() ?? '',
          serverPin: message['server_pin']?.toString() ?? '',
          quicPort: (message['quic_port'] as num?)?.toInt(),
          settings: StreamSettings(
            mode: message['mode']?.toString() ?? 'auto',
            quality: message['quality']?.toString() ?? 'high',
            frameMs: (message['frame_ms'] as num?)?.toInt() ?? 60,
          ),
          startOffset: Duration(milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0),
          queueTrackIds: queue,
          quickStart: message['quick_start'] != false,
          initialPaused: message['initial_paused'] == true,
          listeningContext: context is Map ? Map<String, dynamic>.from(context) : null,
        );
        break;
      case 'play_local':
        final playbackId = (message['playback_id'] as num?)?.toInt() ?? 0;

        if (playbackId <= 0) {
          break;
        }

        final context = message['listening_context'];

        await engine.playLocalFile(
          playbackId: playbackId,
          trackId: message['track_id']?.toString() ?? '',
          trackTitle: message['track_title']?.toString() ?? '',
          filePath: message['file_path']?.toString() ?? '',
          startOffset: Duration(milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0),
          initialPaused: message['initial_paused'] == true,
          listeningContext: context is Map ? Map<String, dynamic>.from(context) : null,
        );
        break;
      case 'stop':
        await engine.stop();
        init.sendPort.send({'type': 'listening_flushed', 'flush_request_id': message['flush_request_id']});
        break;
      case 'pause':
        await engine.pause(playbackId: (message['playback_id'] as num?)?.toInt());
        break;
      case 'resume':
        engine.resume(playbackId: (message['playback_id'] as num?)?.toInt());
        break;
      case 'volume':
        final value = (message['value'] as num?)?.toDouble() ?? 1.0;

        engine.setVolume(value);
        break;
      case 'device':
        final deviceId = (message['device_id'] as num?)?.toInt() ?? kDefaultOutputDeviceId;

        engine.setOutputDevice(deviceId);
        break;
      case 'seek':
        final ms = (message['position_ms'] as num?)?.toInt() ?? 0;

        await engine.seekTo(
          Duration(milliseconds: ms),
          playbackId: (message['playback_id'] as num?)?.toInt(),
          requestId: (message['request_id'] as num?)?.toInt() ?? 0,
        );
        break;
      case 'dispose':
        await engine.dispose();
        init.sendPort.send({'type': 'disposed'});
        receivePort.close();
        Isolate.exit();
      default:
        break;
    }
  }

  receivePort.listen(handleCommand);
}

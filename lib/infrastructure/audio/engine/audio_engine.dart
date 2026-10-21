import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show IsolateNameServer, RootIsolateToken;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:phonolite_local_audio/phonolite_local_audio.dart';
import 'package:phonolite_opus/phonolite_opus.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import 'package:phonolite_app/data/models/audio/audio_source_rejected.dart';
import 'package:phonolite_app/data/models/audio/audio_worker_init.dart';
import 'package:phonolite_app/data/models/audio/stream_settings.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/data/rules/listening_stats/listening_recorder.dart';
import 'package:phonolite_app/data/structures/audio/encoded_audio_cache.dart';
import 'package:phonolite_app/data/structures/audio/pcm_ring_buffer.dart';
import 'package:phonolite_app/infrastructure/audio/output/audio_output_factory.dart';
import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/audio/protocol/raw_header_track_id.dart';
import 'package:phonolite_app/infrastructure/audio/protocol/raw_opus_stream_reader.dart';
import 'package:phonolite_app/infrastructure/platform/audio/audio_device_discovery.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

export 'package:phonolite_app/data/models/audio/stream_settings.dart';
export 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';

part 'package:phonolite_app/infrastructure/audio/engine/buffering/adaptive_buffer_policy.dart';
part 'package:phonolite_app/infrastructure/audio/engine/pipeline/opus_decode_pipeline.dart';
part 'package:phonolite_app/infrastructure/audio/engine/pipeline/pcm_output_pump.dart';
part 'package:phonolite_app/infrastructure/audio/engine/seeking/audio_seek_coordinator.dart';
part 'package:phonolite_app/infrastructure/audio/engine/session/audio_listening_session.dart';
part 'package:phonolite_app/infrastructure/audio/engine/session/audio_output_configuration.dart';
part 'package:phonolite_app/infrastructure/audio/engine/session/playback_session.dart';
part 'package:phonolite_app/infrastructure/audio/engine/sources/local_audio_source.dart';
part 'package:phonolite_app/infrastructure/audio/engine/sources/remote_audio_source.dart';
part 'package:phonolite_app/infrastructure/audio/engine/telemetry/audio_telemetry.dart';
part 'package:phonolite_app/infrastructure/audio/engine/testing/audio_playback_harness.dart';
part 'package:phonolite_app/infrastructure/audio/engine/worker/audio_worker.dart';
part 'package:phonolite_app/infrastructure/audio/engine/worker/audio_worker_engine.dart';

const String _audioWorkerPortName = 'phonolite_audio_worker';

/// Creates an audio backend; tests can supply an implementation without workers.
typedef AudioEngineFactory =
    AudioEngine Function({
      void Function(String message)? onMessage,
      void Function(Duration position, Duration bufferedAhead, double? bitrateKbps, int? rttMs, bool isLocalPlayback)?
      onStats,
      void Function()? onComplete,
      void Function()? onStarted,
      void Function(bool active, bool paused)? onState,
    });

/// Injectable worker startup for tests that do not create a native audio worker.
typedef AudioWorkerSpawner =
    Future<AudioWorkerHandle> Function(SendPort messagePort, RootIsolateToken? rootIsolateToken);

abstract class AudioWorkerHandle {
  void kill();
}

class AudioEngine {
  final void Function(String message)? _onMessage;
  final void Function(Duration position, Duration bufferedAhead, double? bitrateKbps, int? rttMs, bool isLocalPlayback)?
  _onStats;
  final void Function()? _onComplete;
  final void Function()? _onStarted;
  final void Function(bool active, bool paused)? _onState;
  final AudioWorkerSpawner _workerSpawner;
  final bool _usesNativeWorker;
  ReceivePort? _receivePort;
  SendPort? _workerPort;
  Completer<void> _ready = Completer<void>();
  int _workerGeneration = 0;
  AudioWorkerHandle? _isolate;
  bool _disposed = false;
  Future<void>? _initialization;
  Future<void>? _shutdown;
  Completer<void>? _workerShutdown;
  bool _workerFailed = false;
  bool _active = false;
  bool _paused = false;
  bool _sourceRejected = false;
  int _playbackId = 0;
  Map<String, dynamic>? _listeningContext;
  void Function(Map<String, dynamic>)? onListeningSegment;
  Completer<void>? _listeningFlush;
  int _listeningFlushRequestId = 0;
  Future<void>? _stopInFlight;
  bool _stopWaitsForRelease = false;
  int _outputDeviceId = kDefaultOutputDeviceId;
  double _volume = 1.0;
  int _seekRequestId = 0;
  final Map<int, Completer<bool>> _seekRequests = {};
  final RootIsolateToken? _rootIsolateToken = RootIsolateToken.instance;

  AudioEngine({
    AudioWorkerSpawner? workerSpawner,
    void Function(String message)? onMessage,
    void Function(Duration position, Duration bufferedAhead, double? bitrateKbps, int? rttMs, bool isLocalPlayback)?
    onStats,
    void Function()? onComplete,
    void Function()? onStarted,
    void Function(bool active, bool paused)? onState,
  }) : _onMessage = onMessage,
       _onStats = onStats,
       _onComplete = onComplete,
       _onStarted = onStarted,
       _onState = onState,
       _workerSpawner = workerSpawner ?? _spawnNativeWorker,
       _usesNativeWorker = workerSpawner == null;

  /// The server rejected this request; reconnecting cannot repair its source.
  bool get sourceRejected => _sourceRejected;

  bool get hasActivePlayer => _active;

  bool get isPaused => _paused;

  /// Attempts worker startup once; construction alone has no external effects.
  /// Commands wait for its handshake. Recoverable startup failure is reported
  /// through message/state callbacks, and later playback can retry the worker.
  /// Playback also requests initialization for standalone engine users.
  Future<void> initialize() {
    if (_disposed || _shutdown != null) {
      return Future<void>.error(StateError('Audio engine is closed.'));
    }

    final pending = _initialization;
    if (pending != null) {
      return pending;
    }

    final initialization = Completer<void>();

    _initialization = initialization.future;
    _initialize().then(initialization.complete, onError: initialization.completeError);

    return initialization.future;
  }

  Future<void> _initialize() async {
    if (_usesNativeWorker) {
      _shutdownPreviousWorker();
    }

    await _spawnWorker();
  }

  Future<void> stop({bool waitForRelease = false}) {
    final previous = _stopInFlight;
    if (previous != null) {
      return waitForRelease && !_stopWaitsForRelease && _listeningFlush == null
          ? previous.then((_) => stop(waitForRelease: true))
          : previous;
    }

    _stopWaitsForRelease = waitForRelease;

    final stopping = _stopAndFlush(waitForRelease: waitForRelease);

    _stopInFlight = stopping;

    void finishStop() {
      if (identical(_stopInFlight, stopping)) {
        _stopInFlight = null;
        _stopWaitsForRelease = false;
      }
    }

    return stopping.whenComplete(finishStop);
  }

  Future<void> dispose() => _shutdown ??= _close();

  Future<void> _close() async {
    try {
      if (_workerPort != null && !_workerFailed) {
        await stop(waitForRelease: true);

        final shutdown = Completer<void>();

        _workerShutdown = shutdown;
        _workerPort?.send({'cmd': 'dispose'});
        await shutdown.future.timeout(const Duration(seconds: 2));
      } else {
        await stop();
      }
    } on TimeoutException {
      // An unresponsive worker cannot acknowledge release. Forced retirement
      // remains the bounded fallback, after giving orderly shutdown its turn.
      _onMessage?.call('Audio worker did not acknowledge shutdown.');
    } finally {
      _disposed = true;
      _workerGeneration++;
      _cancelPendingSeeks();

      if (!_ready.isCompleted) {
        _ready.complete();
      }

      _receivePort?.close();
      _receivePort = null;

      _isolate?.kill();
      _isolate = null;
      _workerPort = null;
      _workerShutdown = null;
    }
  }

  void configureListening(Map<String, dynamic>? context, {bool updateActive = false, bool discardPending = true}) {
    _listeningContext = context == null ? null : Map.of(context);

    if (updateActive || context == null) {
      _sendCmd({'cmd': 'listening_context', 'context': _listeningContext, 'discard_pending': discardPending});
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _sendCmd({'cmd': 'volume', 'value': _volume});
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    _sendCmd({'cmd': 'device', 'device_id': deviceId});
  }

  Future<List<OutputDevice>> listOutputDevices() => listAudioOutputDevices();

  void pause() {
    _paused = true;
    _sendCmd({'cmd': 'pause', 'playback_id': _playbackId});
  }

  void resume() {
    _paused = false;
    _sendCmd({'cmd': 'resume', 'playback_id': _playbackId});
  }

  Future<void> playTrack({
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
    bool quickStart = true,
    bool initialPaused = false,
  }) async {
    if (_disposed || _shutdown != null) {
      return;
    }

    _sourceRejected = false;
    _cancelPendingSeeks();
    _ensureWorkerForPlayback();

    final playbackId = ++_playbackId;

    _active = true;
    _paused = initialPaused;
    _sendCmd({
      'cmd': 'play',
      'playback_id': playbackId,
      'track_id': track.id,
      'track_title': track.title,
      'listening_context': _listeningContext,
      'base_url': connection.baseUrl,
      'server_pin': connection.trust?.spki ?? '',
      'token': connection.token ?? '',
      'mode': settings.mode,
      'quality': settings.quality,
      'frame_ms': settings.frameMs,
      'start_ms': startOffset.inMilliseconds,
      'queue': queueTrackIds,
      'device_id': _outputDeviceId,
      'quic_port': quicPort,
      'quick_start': quickStart,
      'initial_paused': initialPaused,
    });
  }

  Future<bool> seekTo(Duration position) async {
    if (!_active) {
      return false;
    }

    _seekRequestId++;

    for (final request in _seekRequests.values) {
      if (!request.isCompleted) {
        request.complete(false);
      }
    }

    _seekRequests.clear();

    final requestId = _seekRequestId;
    final ready = Completer<bool>();

    _seekRequests[requestId] = ready;
    _sendCmd({
      'cmd': 'seek',
      'playback_id': _playbackId,
      'position_ms': position.inMilliseconds,
      'request_id': _seekRequestId,
    });

    try {
      return await ready.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      return false;
    } finally {
      _seekRequests.remove(requestId);
    }
  }

  Future<void> playLocalFile({
    required Track track,
    required String filePath,
    String? contentType,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
  }) async {
    if (_disposed || _shutdown != null) {
      return;
    }

    _sourceRejected = false;
    _cancelPendingSeeks();
    _ensureWorkerForPlayback();
    _sendCmd({'cmd': 'stop'});

    final playbackId = ++_playbackId;

    _active = true;
    _paused = initialPaused;
    _sendCmd({
      'cmd': 'play_local',
      'playback_id': playbackId,
      'track_id': track.id,
      'track_title': track.title,
      'file_path': filePath,
      'listening_context': _listeningContext,
      'content_type': contentType ?? '',
      'start_ms': startOffset.inMilliseconds,
      'initial_paused': initialPaused,
      'device_id': _outputDeviceId,
    });
  }

  static void _shutdownPreviousWorker() {
    final existing = IsolateNameServer.lookupPortByName(_audioWorkerPortName);

    if (existing != null) {
      existing.send({'cmd': 'dispose'});
      IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
    }
  }

  static Future<AudioWorkerHandle> _spawnNativeWorker(SendPort messagePort, RootIsolateToken? rootIsolateToken) async =>
      _IsolateAudioWorker(
        await Isolate.spawn<AudioWorkerInit>(
          _audioWorkerMain,
          AudioWorkerInit(messagePort, rootIsolateToken),
          onError: messagePort,
          onExit: messagePort,
        ),
      );

  Future<void> _spawnWorker() async {
    final generation = ++_workerGeneration;
    final previousReady = _ready;

    if (!previousReady.isCompleted) {
      previousReady.complete();
    }

    _receivePort?.close();

    _isolate?.kill();
    _isolate = null;
    _workerPort = null;
    _workerFailed = false;

    final ready = Completer<void>();

    _ready = ready;

    final receivePort = ReceivePort();

    _receivePort = receivePort;

    void receiveWorkerMessage(Object? message) {
      if (_disposed || generation != _workerGeneration || _workerFailed) {
        return;
      }

      _handleWorkerMessage(message);
    }

    receivePort.listen(receiveWorkerMessage);

    AudioWorkerHandle isolate;

    try {
      isolate = await _workerSpawner(receivePort.sendPort, _rootIsolateToken);
    } catch (error) {
      if (!_disposed && generation == _workerGeneration) {
        _failWorker('Audio worker failed to start: $error');
      }

      if (!ready.isCompleted) {
        ready.complete();
      }

      return;
    }

    if (_disposed || generation != _workerGeneration || _workerFailed) {
      isolate.kill();

      if (!ready.isCompleted) {
        ready.complete();
      }

      return;
    }

    _isolate = isolate;
  }

  void _failWorker(String message) {
    if (_disposed || _workerFailed) {
      return;
    }

    _workerFailed = true;
    _workerPort = null;

    _receivePort?.close();
    _receivePort = null;

    _isolate?.kill();
    _isolate = null;

    if (!_ready.isCompleted) {
      _ready.complete();
    }

    _cancelPendingSeeks();
    _active = false;
    _paused = false;

    _onMessage?.call(message);
    _onState?.call(false, false);
  }

  void _ensureWorkerForPlayback() {
    if (_disposed || _shutdown != null) {
      return;
    }

    if (_initialization == null) {
      unawaited(initialize());

      return;
    }

    if (!_workerFailed) {
      return;
    }

    if (_usesNativeWorker) {
      _shutdownPreviousWorker();
    }

    unawaited(_spawnWorker());
  }

  void _handleWorkerMessage(dynamic message) {
    if (message == null && _workerShutdown != null) {
      if (!_workerShutdown!.isCompleted) {
        _workerShutdown!.complete();
      }

      return;
    }

    if (!_disposed && (message == null || message is List)) {
      final workerError = message is List && message.isNotEmpty ? message.first.toString() : 'Unknown worker error';

      _failWorker(message == null ? 'Audio worker exited unexpectedly.' : 'Audio worker failed: $workerError');

      return;
    }

    if (message is Map && message['type'] == 'disposed') {
      final shutdown = _workerShutdown;

      if (shutdown != null && !shutdown.isCompleted) {
        shutdown.complete();
      }

      return;
    }

    if (message is SendPort) {
      _workerPort = message;
      // Configuration precedes playback queued while this worker was starting.
      message.send({'cmd': 'volume', 'value': _volume});
      message.send({'cmd': 'device', 'device_id': _outputDeviceId});
      message.send({'cmd': 'listening_context', 'context': _listeningContext});

      if (!_ready.isCompleted) {
        _ready.complete();
      }

      return;
    }

    if (message is! Map) {
      return;
    }

    // Listening records belong to their captured session even after the UI
    // changes track. Never discard the previous track's final checkpoint.
    if (message['type'] == 'listening_segment') {
      final event = message['event'];

      if (event is Map) {
        onListeningSegment?.call(Map<String, dynamic>.from(event));
      }

      return;
    }

    if (message['type'] == 'listening_flushed') {
      final pending = _listeningFlush;

      if (message['flush_request_id'] == _listeningFlushRequestId && pending != null && !pending.isCompleted) {
        pending.complete();
      }

      return;
    }

    final messagePlaybackId = (message['playback_id'] as num?)?.toInt();

    if (messagePlaybackId != null && messagePlaybackId != _playbackId) {
      return;
    }

    final type = message['type'];

    switch (type) {
      case 'seek_ready':
      case 'seek_failed':
        final requestId = (message['request_id'] as num?)?.toInt();
        final request = _seekRequests.remove(requestId);

        if (request != null && !request.isCompleted) {
          request.complete(type == 'seek_ready');
        }

        break;
      case 'message':
        final text = message['text']?.toString();

        if (text != null) {
          final handler = _onMessage;

          if (handler != null) {
            handler(text);
          }
        }

        break;
      case 'stats':
        final positionMs = (message['position_ms'] as num?)?.toInt() ?? 0;
        final bufferedMs = (message['buffered_ms'] as num?)?.toInt() ?? 0;
        final rttMs = (message['rtt_ms'] as num?)?.toInt();
        final handler = _onStats;

        if (handler != null) {
          handler(
            Duration(milliseconds: positionMs),
            Duration(milliseconds: bufferedMs),
            (message['bitrate_kbps'] as num?)?.toDouble(),
            rttMs,
            message['local'] == true,
          );
        }

        break;
      case 'complete':
        final handler = _onComplete;

        if (handler != null) {
          handler();
        }

        break;
      case 'started':
        final handler = _onStarted;

        if (handler != null) {
          handler();
        }

        break;
      case 'state':
        final active = message['active'] == true;
        final paused = message['paused'] == true;

        _active = active;
        _paused = paused;
        _sourceRejected = message['source_rejected'] == true;
        _onState?.call(active, paused);

        if (_sourceRejected) {
          _cancelPendingSeeks();
        }

        break;
      default:
        break;
    }
  }

  Future<void> _stopAndFlush({bool waitForRelease = false}) async {
    _cancelPendingSeeks();
    _playbackId++;
    _active = false;
    _paused = false;
    // The worker acknowledges only after closing its decoder/file. Deletion
    // must wait for that acknowledgment even when listening stats are disabled.
    final waitForAcknowledgment =
        !_workerFailed && (waitForRelease || (_listeningContext != null && _workerPort != null));
    final flush = waitForAcknowledgment ? Completer<void>() : null;

    _listeningFlush = flush;

    if (_initialization == null) {
      return;
    }

    _sendCmd({'cmd': 'stop', 'flush_request_id': ++_listeningFlushRequestId});

    if (flush != null) {
      try {
        await flush.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        if (waitForRelease) {
          rethrow;
        }
        // A terminated worker cannot provide its uncheckpointed tail.
      } finally {
        if (identical(_listeningFlush, flush)) {
          _listeningFlush = null;
        }
      }
    }
  }

  void _sendCmd(Map<String, dynamic> message) {
    if (_disposed || _workerFailed) {
      return;
    }

    final generation = _workerGeneration;

    if (!_ready.isCompleted) {
      // The handshake sends current configuration before queued playback.
      final command = message['cmd'];

      if (command == 'volume' || command == 'device' || command == 'listening_context') {
        return;
      }

      void sendWhenReady(void _) {
        if (_disposed || _workerFailed || generation != _workerGeneration) {
          return;
        }

        final playbackId = message['playback_id'];

        if (playbackId != null && playbackId != _playbackId) {
          return;
        }

        _workerPort?.send(message);
      }

      _ready.future.then(sendWhenReady);

      return;
    }

    _workerPort?.send(message);
  }

  void _cancelPendingSeeks() {
    for (final request in _seekRequests.values) {
      if (!request.isCompleted) {
        request.complete(false);
      }
    }

    _seekRequests.clear();
  }
}

class _IsolateAudioWorker implements AudioWorkerHandle {
  final Isolate isolate;

  _IsolateAudioWorker(this.isolate);

  @override
  void kill() => isolate.kill(priority: Isolate.immediate);
}

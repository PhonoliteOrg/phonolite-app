import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show IsolateNameServer, RootIsolateToken;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'models.dart';
import 'listening_recorder.dart';
import 'pcm_ring_buffer.dart';
import 'encoded_audio_cache.dart';
import 'raw_opus_stream.dart';
import 'server_connection.dart';
import 'package:phonolite_local_audio/phonolite_local_audio.dart';
import 'package:phonolite_opus/phonolite_opus.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

const _audioWorkerPortName = 'phonolite_audio_worker';
const MethodChannel _androidAudioOutputChannel = MethodChannel(
  'phonolite/audio_output',
);

class StreamSettings {
  const StreamSettings({
    required this.mode,
    required this.quality,
    this.frameMs = 20,
  });

  final String mode;
  final String quality;
  final int frameMs;
}

/// Creates an audio backend; tests can supply an implementation without workers.
typedef AudioEngineFactory =
    AudioEngine Function({
      void Function(String message)? onMessage,
      void Function(
        Duration position,
        Duration bufferedAhead,
        double? bitrateKbps,
        int? rttMs,
        bool isLocalPlayback,
      )?
      onStats,
      void Function()? onComplete,
      void Function()? onStarted,
      void Function(bool active, bool paused)? onState,
    });

/// Injectable worker startup for tests that do not create a native audio worker.
typedef AudioWorkerSpawner =
    Future<AudioWorkerHandle> Function(
      SendPort messagePort,
      RootIsolateToken? rootIsolateToken,
    );

abstract class AudioWorkerHandle {
  void kill();
}

class _IsolateAudioWorker implements AudioWorkerHandle {
  _IsolateAudioWorker(this.isolate);
  final Isolate isolate;
  @override
  void kill() => isolate.kill(priority: Isolate.immediate);
}

class _AudioSourceRejected implements Exception {
  const _AudioSourceRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class AudioEngine {
  AudioEngine({
    void Function(String message)? onMessage,
    void Function(
      Duration position,
      Duration bufferedAhead,
      double? bitrateKbps,
      int? rttMs,
      bool isLocalPlayback,
    )?
    onStats,
    void Function()? onComplete,
    void Function()? onStarted,
    void Function(bool active, bool paused)? onState,
    AudioWorkerSpawner? workerSpawner,
  }) : _onMessage = onMessage,
       _onStats = onStats,
       _onComplete = onComplete,
       _onStarted = onStarted,
       _onState = onState,
       _workerSpawner = workerSpawner ?? _spawnNativeWorker,
       _usesNativeWorker = workerSpawner == null {
    if (_usesNativeWorker) _shutdownPreviousWorker();
    unawaited(_spawnWorker());
  }

  final void Function(String message)? _onMessage;
  final void Function(
    Duration position,
    Duration bufferedAhead,
    double? bitrateKbps,
    int? rttMs,
    bool isLocalPlayback,
  )?
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

  void configureListening(
    Map<String, dynamic>? context, {
    bool updateActive = false,
    bool discardPending = true,
  }) {
    _listeningContext = context == null ? null : Map.of(context);
    if (updateActive || context == null) {
      _sendCmd({
        'cmd': 'listening_context',
        'context': _listeningContext,
        'discard_pending': discardPending,
      });
    }
  }

  int _outputDeviceId = kDefaultOutputDeviceId;
  double _volume = 1.0;
  int _seekRequestId = 0;
  final Map<int, Completer<bool>> _seekRequests = {};
  final RootIsolateToken? _rootIsolateToken = RootIsolateToken.instance;

  static void _shutdownPreviousWorker() {
    final existing = IsolateNameServer.lookupPortByName(_audioWorkerPortName);
    if (existing != null) {
      existing.send({'cmd': 'dispose'});
      IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
    }
  }

  static Future<AudioWorkerHandle> _spawnNativeWorker(
    SendPort messagePort,
    RootIsolateToken? rootIsolateToken,
  ) async => _IsolateAudioWorker(
    await Isolate.spawn<_AudioWorkerInit>(
      _audioWorkerMain,
      _AudioWorkerInit(messagePort, rootIsolateToken),
      onError: messagePort,
      onExit: messagePort,
    ),
  );

  Future<void> _spawnWorker() async {
    final generation = ++_workerGeneration;
    final previousReady = _ready;
    if (!previousReady.isCompleted) previousReady.complete();
    _receivePort?.close();
    _isolate?.kill();
    _isolate = null;
    _workerPort = null;
    _workerFailed = false;
    final ready = Completer<void>();
    _ready = ready;
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen((message) {
      if (_disposed || generation != _workerGeneration || _workerFailed) return;
      _handleWorkerMessage(message);
    });
    AudioWorkerHandle isolate;
    try {
      isolate = await _workerSpawner(receivePort.sendPort, _rootIsolateToken);
    } catch (error) {
      if (!_disposed && generation == _workerGeneration) {
        _failWorker('Audio worker failed to start: $error');
      }
      if (!ready.isCompleted) ready.complete();
      return;
    }
    if (_disposed || generation != _workerGeneration || _workerFailed) {
      isolate.kill();
      if (!ready.isCompleted) ready.complete();
      return;
    }
    _isolate = isolate;
  }

  void _failWorker(String message) {
    if (_disposed || _workerFailed) return;
    _workerFailed = true;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill();
    _isolate = null;
    if (!_ready.isCompleted) _ready.complete();
    _cancelPendingSeeks();
    _active = false;
    _paused = false;
    _onMessage?.call(message);
    _onState?.call(false, false);
  }

  void _ensureWorkerForPlayback() {
    if (_disposed || !_workerFailed) return;
    if (_usesNativeWorker) _shutdownPreviousWorker();
    unawaited(_spawnWorker());
  }

  void _handleWorkerMessage(dynamic message) {
    if (!_disposed && (message == null || message is List)) {
      final workerError = message is List && message.isNotEmpty
          ? message.first.toString()
          : 'Unknown worker error';
      _failWorker(
        message == null
            ? 'Audio worker exited unexpectedly.'
            : 'Audio worker failed: $workerError',
      );
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
      if (message['flush_request_id'] == _listeningFlushRequestId &&
          pending != null &&
          !pending.isCompleted) {
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
        if (_sourceRejected) _cancelPendingSeeks();
        break;
      default:
        break;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_ready.isCompleted) {
      _workerPort?.send({'cmd': 'dispose'});
    }
    _workerGeneration++;
    if (!_ready.isCompleted) _ready.complete();
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill();
    _isolate = null;
    _workerPort = null;
  }

  Future<void> stop({bool waitForRelease = false}) {
    final previous = _stopInFlight;
    if (previous != null) {
      return waitForRelease && !_stopWaitsForRelease
          ? previous.then((_) => stop(waitForRelease: true))
          : previous;
    }
    _stopWaitsForRelease = waitForRelease;
    final stopping = _stopAndFlush(waitForRelease: waitForRelease);
    _stopInFlight = stopping;
    return stopping.whenComplete(() {
      if (identical(_stopInFlight, stopping)) {
        _stopInFlight = null;
        _stopWaitsForRelease = false;
      }
    });
  }

  Future<void> _stopAndFlush({bool waitForRelease = false}) async {
    _cancelPendingSeeks();
    _playbackId++;
    _active = false;
    _paused = false;
    // The worker acknowledges only after closing its decoder/file. Deletion
    // must wait for that acknowledgment even when listening stats are disabled.
    final waitForAcknowledgment =
        !_workerFailed &&
        (waitForRelease || (_listeningContext != null && _workerPort != null));
    final flush = waitForAcknowledgment ? Completer<void>() : null;
    _listeningFlush = flush;
    _sendCmd({'cmd': 'stop', 'flush_request_id': ++_listeningFlushRequestId});
    if (flush != null) {
      try {
        await flush.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        if (waitForRelease) rethrow;
        // A terminated worker cannot provide its uncheckpointed tail.
      } finally {
        if (identical(_listeningFlush, flush)) _listeningFlush = null;
      }
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

  Future<List<OutputDevice>> listOutputDevices() async {
    final devices = <OutputDevice>[
      OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default'),
    ];
    if (Platform.isWindows) {
      final bindings = _WaveOutBindings();
      final count = bindings.waveOutGetNumDevs();
      for (var i = 0; i < count; i++) {
        final caps = calloc<WAVEOUTCAPSW>();
        final result = bindings.waveOutGetDevCapsW(
          i,
          caps,
          ffi.sizeOf<WAVEOUTCAPSW>(),
        );
        if (result == MMSYSERR_NOERROR) {
          final name = _utf16ArrayToString(caps.ref.szPname);
          devices.add(
            OutputDevice(id: i, name: name.isEmpty ? 'Device $i' : name),
          );
        }
        calloc.free(caps);
      }
      return devices;
    }
    if (Platform.isMacOS) {
      final bindings = _CoreAudioBindings();
      final count = bindings.getOutputDeviceCount();
      for (var i = 0; i < count; i++) {
        final deviceId = bindings.getOutputDeviceId(i).toUnsigned(32);
        if (deviceId == 0) {
          continue;
        }
        final name = bindings.getOutputDeviceName(deviceId);
        devices.add(
          OutputDevice(
            id: deviceId,
            name: name?.isNotEmpty == true ? name! : 'Device $i',
          ),
        );
      }
      return devices;
    }
    if (Platform.isAndroid) {
      try {
        final result = await _androidAudioOutputChannel
            .invokeMethod<List<dynamic>>('listOutputDevices');
        if (result == null) {
          return devices;
        }
        for (final item in result) {
          if (item is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(item);
          final id = (map['id'] as num?)?.toInt();
          final name = map['name']?.toString().trim();
          if (id == null || name == null || name.isEmpty) {
            continue;
          }
          final alreadyAdded = devices.any((device) => device.id == id);
          if (!alreadyAdded) {
            devices.add(OutputDevice(id: id, name: name));
          }
        }
      } catch (_) {}
      return devices;
    }
    return devices;
  }

  void pause() {
    _paused = true;
    _sendCmd({'cmd': 'pause', 'playback_id': _playbackId});
  }

  void resume() {
    _paused = false;
    _sendCmd({'cmd': 'resume', 'playback_id': _playbackId});
  }

  /// The server rejected this request; reconnecting cannot repair its source.
  bool get sourceRejected => _sourceRejected;

  bool get hasActivePlayer => _active;

  bool get isPaused => _paused;

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
    if (_disposed) return;
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

  void _sendCmd(Map<String, dynamic> message) {
    if (_disposed || _workerFailed) return;
    final generation = _workerGeneration;
    if (!_ready.isCompleted) {
      // The handshake sends current configuration before queued playback.
      final command = message['cmd'];
      if (command == 'volume' ||
          command == 'device' ||
          command == 'listening_context') {
        return;
      }
      _ready.future.then((_) {
        if (_disposed || _workerFailed || generation != _workerGeneration) {
          return;
        }
        final playbackId = message['playback_id'];
        if (playbackId != null && playbackId != _playbackId) {
          return;
        }
        _workerPort?.send(message);
      });
      return;
    }
    _workerPort?.send(message);
  }

  Future<bool> seekTo(Duration position) async {
    if (!_active) {
      return false;
    }
    _seekRequestId++;
    for (final request in _seekRequests.values) {
      if (!request.isCompleted) request.complete(false);
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
    if (_disposed) return;
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

  void _cancelPendingSeeks() {
    for (final request in _seekRequests.values) {
      if (!request.isCompleted) request.complete(false);
    }
    _seekRequests.clear();
  }
}

class _AudioWorkerEngine {
  _AudioWorkerEngine({
    required void Function(Map<String, dynamic> message) send,
  }) : _send = send;

  final void Function(Map<String, dynamic> message) _send;
  int _playbackId = 0;
  _PlaybackSession? _session;
  int _startGeneration = 0;
  int _listeningRevision = 0;
  Map<String, dynamic>? _latestListeningContext;
  Future<void>? _stopInFlight;
  QuicClient? _idleConnection;
  String? _idleConnectionKey;
  String? _idleTrackId;

  double _volume = 1.0;
  int _outputDeviceId = kDefaultOutputDeviceId;

  void configureListening(
    Map<String, dynamic>? context, {
    bool discardPending = true,
  }) {
    _listeningRevision++;
    _latestListeningContext = context;
    final session = _session;
    if (session != null) {
      unawaited(
        session.configureListening(context, discardPending: discardPending),
      );
    }
  }

  Future<void> dispose() async {
    await stop();
  }

  Future<void> stop({bool notify = true}) {
    if (notify) _startGeneration++;
    final previous = _stopInFlight;
    if (previous != null) return previous;
    final stopping = _stopSession(notify);
    _stopInFlight = stopping;
    return stopping.whenComplete(() {
      if (identical(_stopInFlight, stopping)) _stopInFlight = null;
    });
  }

  Future<void> _stopSession(bool notify) async {
    final stoppedPlaybackId = _playbackId;
    _idleConnection?.close();
    _idleConnection = null;
    final previous = _session;
    _session = null;
    await previous?.requestStop(outcome: notify ? 'cancelled' : 'superseded');
    if (notify) {
      _send({
        'type': 'state',
        'active': false,
        'paused': false,
        'playback_id': stoppedPlaybackId,
      });
    }
  }

  Future<void> pause({int? playbackId}) async {
    if (playbackId != null && playbackId != _playbackId) {
      return;
    }
    try {
      await _session?.pause();
    } catch (error) {
      _session?.requestStop(outcome: 'output_error');
      _send({'type': 'message', 'text': 'Audio pause failed: $error'});
      _send({
        'type': 'state',
        'active': false,
        'paused': false,
        'playback_id': _playbackId,
      });
    }
  }

  void resume({int? playbackId}) {
    if (playbackId != null && playbackId != _playbackId) {
      return;
    }
    try {
      _session?.resume();
    } catch (error) {
      _session?.requestStop(outcome: 'output_error');
      _send({'type': 'message', 'text': 'Audio resume failed: $error'});
      _send({
        'type': 'state',
        'active': false,
        'paused': false,
        'playback_id': _playbackId,
      });
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _session?.setVolume(_volume);
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    _session?.setOutputDevice(deviceId);
  }

  Future<void> seekTo(
    Duration position, {
    int? playbackId,
    int requestId = 0,
  }) async {
    if (playbackId != null && playbackId != _playbackId) {
      _send({
        'type': 'seek_failed',
        'request_id': requestId,
        'playback_id': playbackId,
      });
      return;
    }
    final session = _session;
    if (session == null) {
      _send({
        'type': 'seek_failed',
        'request_id': requestId,
        'playback_id': _playbackId,
      });
      return;
    }
    await session.seekTo(position, requestId: requestId);
  }

  Future<void> playTrack({
    required int playbackId,
    required String trackId,
    required String trackTitle,
    required String baseUrl,
    required String token,
    String serverPin = '',
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
    bool quickStart = true,
    bool initialPaused = false,
    Map<String, dynamic>? listeningContext,
  }) async {
    final generation = ++_startGeneration;
    final listeningRevision = _listeningRevision;
    final key = '$baseUrl|$quicPort|$token|$serverPin';
    var reusable = _session?.takeConnection(key, trackId);
    if (reusable == null &&
        _idleConnectionKey == key &&
        _idleTrackId != trackId) {
      reusable = _idleConnection;
      _idleConnection = null;
    }
    await stop(notify: false);
    if (generation != _startGeneration) return;
    _playbackId = playbackId;
    final session = _PlaybackSession.remote(
      send: _send,
      reusableConnection: reusable,
      releaseConnection: (client) {
        if (_playbackId != playbackId) {
          client.close();
          return;
        }
        _idleConnection?.close();
        _idleConnection = client;
        _idleConnectionKey = key;
        _idleTrackId = trackId;
      },
      playbackId: playbackId,
      getPlaybackId: () => _playbackId,
      trackId: trackId,
      trackTitle: trackTitle,
      baseUrl: baseUrl,
      token: token,
      serverPin: serverPin,
      quicPort: quicPort,
      settings: settings,
      startOffset: startOffset,
      queueTrackIds: queueTrackIds,
      quickStart: quickStart,
      initialPaused: initialPaused,
      volume: _volume,
      outputDeviceId: _outputDeviceId,
      listeningContext: listeningRevision == _listeningRevision
          ? listeningContext
          : _latestListeningContext,
    );
    _session = session;
    try {
      await session.run();
    } finally {
      if (identical(_session, session)) {
        _session = null;
      }
    }
  }

  Future<void> playLocalFile({
    required int playbackId,
    required String trackId,
    required String trackTitle,
    required String filePath,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
    Map<String, dynamic>? listeningContext,
  }) async {
    final generation = ++_startGeneration;
    final listeningRevision = _listeningRevision;
    await stop(notify: false);
    if (generation != _startGeneration) return;
    _playbackId = playbackId;
    final session = _PlaybackSession.local(
      send: _send,
      playbackId: playbackId,
      getPlaybackId: () => _playbackId,
      trackId: trackId,
      trackTitle: trackTitle,
      filePath: filePath,
      startOffset: startOffset,
      initialPaused: initialPaused,
      volume: _volume,
      outputDeviceId: _outputDeviceId,
      listeningContext: listeningRevision == _listeningRevision
          ? listeningContext
          : _latestListeningContext,
    );
    _session = session;
    try {
      await session.run();
    } finally {
      if (identical(_session, session)) {
        _session = null;
      }
    }
  }
}

class _PlaybackSession {
  _PlaybackSession.remote({
    QuicClient? reusableConnection,
    required void Function(QuicClient) releaseConnection,
    required void Function(Map<String, dynamic> message) send,
    required int playbackId,
    required int Function() getPlaybackId,
    required this.trackId,
    required this.trackTitle,
    required this.baseUrl,
    required this.token,
    this.serverPin = '',
    required this.quicPort,
    required this.settings,
    required this.startOffset,
    required this.queueTrackIds,
    required this.quickStart,
    required bool initialPaused,
    required double volume,
    required int outputDeviceId,
    Map<String, dynamic>? listeningContext,
    OpusDecoder Function(int sampleRate, int channels)? decoderFactory,
    AudioPcmOutput Function(int sampleRate, int channels, int deviceId)?
    outputFactory,
  }) : _send = send,
       _playbackId = playbackId,
       _getPlaybackId = getPlaybackId,
       _volume = volume,
       _outputDeviceId = outputDeviceId,
       localFilePath = null,
       _decoderFactory = decoderFactory,
       _outputFactory = outputFactory,
       _quic = reusableConnection,
       _releaseConnection = releaseConnection {
    _userPaused = initialPaused;
    _paused = initialPaused;
    _listening = ListeningRecorder(
      emit: (event) => _send({'type': 'listening_segment', 'event': event}),
      playbackId: playbackId,
      context: listeningContext,
    );
  }

  _PlaybackSession.local({
    required void Function(Map<String, dynamic> message) send,
    required int playbackId,
    required int Function() getPlaybackId,
    required this.trackId,
    required this.trackTitle,
    required String filePath,
    required this.startOffset,
    required bool initialPaused,
    required double volume,
    required int outputDeviceId,
    Map<String, dynamic>? listeningContext,
    AudioPcmOutput Function(int sampleRate, int channels, int deviceId)?
    outputFactory,
  }) : _send = send,
       _playbackId = playbackId,
       _getPlaybackId = getPlaybackId,
       baseUrl = '',
       token = '',
       serverPin = '',
       quicPort = null,
       settings = const StreamSettings(mode: 'local', quality: 'source'),
       queueTrackIds = const <String>[],
       quickStart = true,
       _volume = volume,
       _outputDeviceId = outputDeviceId,
       localFilePath = filePath,
       _decoderFactory = null,
       _outputFactory = outputFactory,
       _releaseConnection = null {
    _userPaused = initialPaused;
    _paused = initialPaused;
    _listening = ListeningRecorder(
      emit: (event) => _send({'type': 'listening_segment', 'event': event}),
      playbackId: playbackId,
      context: listeningContext,
    );
  }

  late final ListeningRecorder _listening;
  Future<void>? _stopCompletion;

  int _listeningContextRevision = 0;

  Future<void> configureListening(
    Map<String, dynamic>? context, {
    bool discardPending = true,
  }) async {
    final revision = ++_listeningContextRevision;
    if (context == null && discardPending) {
      _listening.setContext(null);
      return;
    }
    final player = _player;
    if (player != null) {
      try {
        // Account changes/re-enabling do not claim audio consumed before the
        // new context. Keep queue accounting and the previous recorder aligned.
        final epoch = _outputEpoch;
        final done = await _collectListeningSamples(player);
        if (epoch == _outputEpoch && identical(player, _player)) {
          _playedSamples += done;
        }
      } catch (_) {}
    }
    if (revision != _listeningContextRevision || _stopRequested) return;
    if (context == null) _listening.flush(endReason: 'interrupted');
    _listening.setContext(context);
  }

  Future<int> _collectListeningSamples(_NativeAudioPlayer player) async {
    // A replacement header can change the decoder format during the native
    // call. Convert this output's samples using its captured format.
    final sampleRate = _playerSampleRate ?? _sampleRate;
    final channels = _playerChannels ?? _channels;
    final done = await player.collectDoneSamples();
    _listening.addSamples(done, sampleRate: sampleRate, channels: channels);
    return done;
  }

  Future<void> _disposeReplacedOutput(_NativeAudioPlayer player) async {
    try {
      player.pause();
      if (_listening.enabled) await _collectListeningSamples(player);
    } catch (_) {}
    player.dispose();
    _listening.flush();
  }

  final void Function(Map<String, dynamic> message) _send;
  final int _playbackId;
  final int Function() _getPlaybackId;
  final String trackId;
  final String trackTitle;
  final String baseUrl;
  final String token;
  final String serverPin;
  final int? quicPort;
  final StreamSettings settings;
  final Duration startOffset;
  final List<String> queueTrackIds;
  final bool quickStart;
  final String? localFilePath;
  final void Function(QuicClient)? _releaseConnection;
  final OpusDecoder Function(int sampleRate, int channels)? _decoderFactory;
  final AudioPcmOutput Function(int sampleRate, int channels, int deviceId)?
  _outputFactory;
  QuicClient? takeConnection(String key, String nextTrackId) {
    if (_isLocalFile ||
        trackId == nextTrackId ||
        '$baseUrl|$quicPort|$token|$serverPin' != key) {
      return null;
    }
    final client = _quic;
    _quic = null;
    return client;
  }

  double _volume;
  int _outputDeviceId;
  int _baseOffsetMs = 0;
  int? _pendingSeekMs;
  int? _pendingSeekRequestedAtMs;
  int _nextSeekId = 0;
  int? _pendingSeekId;
  int? _activeSeekId;
  int _seekRequestGeneration = 0;
  int _seekReadyRequestId = 0;
  int _outputEpoch = 0;
  Timer? _seekDeadline;
  final _encodedCache = EncodedAudioCache();
  final _rawReader = RawOpusStreamReader();
  EncodedAudioCursor? _decodeCursor;
  EncodedAudioSegment? _incomingSegment;
  EncodedAudioCursor? _cachedSeek;
  int? _decodedThroughSample;
  bool _remoteContinuation = false;
  bool _waitingForHeader = false;
  int _incomingStartMs = 0;
  int? _incomingRangeEndMs;
  bool _incomingEndOfTrack = true;
  String _sourceVersion = '';
  int? _transportRequestId;
  Future<void>? _outputReset;
  int _lastBufferReportAtMs = 0;
  int _lastReportedBufferMs = -1;
  int _lastReportedTargetMs = -1;
  bool _pumpRunning = false;
  bool _pumpSuspended = false;
  bool _quickStart = false;
  bool _startupBufferFilled = false;
  bool _isLoopbackHost = false;
  int _networkProfileLevel = 0;
  int _stableBufferTicks = 0;
  int? _lastObservedRttMs;

  bool _stopRequested = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _autoPaused = false;
  bool _reportedStart = false;
  bool _startedPlayback = false;
  bool _streamEnded = false;
  bool _remotePlaybackComplete = false;
  int _lastQuicStatsLogAtMs = 0;

  int _sampleRate = 48000;
  int _channels = 2;
  int _frameSamples = 0;

  double _prebufferSeconds = 0.3;
  double _rebufferMinSeconds = 0.08;
  double _rebufferTargetSeconds = 0.3;
  static const double _prebufferSecondsLocal = 0.1;
  static const double _rebufferMinSecondsLocal = 0.04;
  static const double _rebufferTargetSecondsLocal = 0.15;
  static const double _seekStartSeconds = 0.05;
  static const double _seekCatchupMinSeconds = 0.2;
  static const double _seekCatchupTargetSeconds = 0.4;
  static const int _pumpChunkMs = 40;
  static const bool _serverBackpressureEnabled = true;

  int _prebufferTargetSamples = 0;
  int _rebufferMinSamples = 0;
  int _rebufferTargetSamples = 0;
  int _pumpChunkSamples = 0;

  QuicClient? _quic;
  OpusDecoder? _decoder;
  LocalAudioDecoder? _localDecoder;
  _NativeAudioPlayer? _player;
  int? _playerSampleRate;
  int? _playerChannels;
  int? _playerDeviceId;
  PcmRingBuffer? _buffer;
  Timer? _statsTimer;
  bool _statsCollectionInFlight = false;
  static const int _quicStatsLogIntervalMs = 2000;

  int _queuedToPlayerSamples = 0;
  int _playedSamples = 0;
  int _bytesReceived = 0;
  int _lastBitrateBytes = 0;
  DateTime? _lastBitrateAt;

  void _sendPlaybackMessage(Map<String, dynamic> message) {
    _send({'playback_id': _playbackId, ...message});
  }

  bool get _isLocalFile => localFilePath != null;

  bool get _isActive => !_stopRequested && _playbackId == _getPlaybackId();

  Future<void> requestStop({String outcome = 'cancelled'}) =>
      _stopCompletion ??= _stopPlayback(outcome);

  Future<void> _stopPlayback(String outcome) async {
    _outputEpoch++;
    _failSeek(outcome);
    _stopRequested = true;
    _stopStats();
    _pumpSuspended = true;
    _streamEnded = true;
    _buffer = null;
    _decoder?.dispose();
    _decoder = null;
    _localDecoder?.close();
    _localDecoder = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        player.pause();
        if (_listening.enabled) {
          await _collectListeningSamples(player);
        }
      } catch (_) {}
      player.dispose();
    }
    _listening.flush(
      endReason: outcome == 'superseded'
          ? 'skipped'
          : outcome == 'cancelled'
          ? 'stopped'
          : 'interrupted',
    );
    _playerSampleRate = null;
    _playerChannels = null;
    _playerDeviceId = null;
    _quic?.close();
    _quic = null;
  }

  Future<void> pause() async {
    _userPaused = true;
    _reportBuffer(force: true);
    if (_paused) {
      return;
    }
    _paused = true;
    final player = _player;
    if (player != null) {
      player.pause();
      try {
        final done = await _collectListeningSamples(player);
        _playedSamples += done;
      } catch (_) {}
      _listening.flush();
      _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': true});
    }
  }

  void resume() {
    _userPaused = false;
    _reportBuffer(force: true);
    if (!_paused) {
      return;
    }
    _paused = false;
    _userPaused = false;
    _autoPaused = false;
    final player = _player;
    if (player != null) {
      player.resume();
      _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': false});
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
  }

  Future<void> seekTo(Duration position, {int requestId = 0}) async {
    final output = _player;
    if (output != null) {
      try {
        final done = await _collectListeningSamples(output);
        _playedSamples += done;
      } catch (_) {}
    }
    _listening.flush();
    _seekRequestGeneration++;
    final generation = _seekRequestGeneration;
    _failSeek('superseded');
    _seekReadyRequestId = requestId;
    final ms = math.max(0, position.inMilliseconds);
    _pendingSeekRequestedAtMs = DateTime.now().millisecondsSinceEpoch;
    _quickStart = true;
    _streamEnded = false;
    _remotePlaybackComplete = false;
    _seekDeadline = Timer(const Duration(seconds: 5), () {
      if (!_isActive || _seekReadyRequestId != requestId) return;
      _failSeek('timeout');
      requestStop(outcome: 'seek_timeout');
      _sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false});
    });
    if (_isLocalFile) {
      _pendingSeekMs = ms;
      return;
    }
    final quic = _quic;
    if (quic == null) {
      _failSeek('unavailable');
      return;
    }
    final cached = _encodedCache.seek(ms);
    _decodeCursor = null;
    _decodedThroughSample = null;
    _cachedSeek = null;
    _incomingSegment = null;
    _rawReader.reset();
    _outputReset = _resetOutputForSeek(ms).catchError((Object error) {
      if (generation != _seekRequestGeneration || !_isActive) return;
      _log('Unable to flush audio output: $error');
      _failSeek('output_error');
      requestStop(outcome: 'output_error');
      _sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false});
    });
    if (cached != null) {
      // A cached seek requires neither server transcoding nor retransmission.
      quic.suspendAudio();
      _waitingForHeader = false;
      _pendingSeekId = null;
      _cachedSeek = cached;
      _remoteContinuation = false;
      _reportBuffer(force: true, suspended: true);
      return;
    }
    _requestRemoteRange(ms, continuation: false);
  }

  void _failSeek(String outcome) {
    _seekDeadline?.cancel();
    _seekDeadline = null;
    final requestId = _seekReadyRequestId;
    if (requestId != 0) {
      _sendPlaybackMessage({
        'type': 'seek_failed',
        'request_id': requestId,
        'outcome': outcome,
      });
      _seekReadyRequestId = 0;
    }
  }

  void _markSeekReady() {
    _seekDeadline?.cancel();
    _seekDeadline = null;
    final requestId = _seekReadyRequestId;
    if (requestId != 0) {
      _sendPlaybackMessage({'type': 'seek_ready', 'request_id': requestId});
      _seekReadyRequestId = 0;
    }
  }

  Future<void> _resetOutputForSeek(int ms) async {
    final epoch = ++_outputEpoch;
    _pumpSuspended = true;
    _buffer = null;
    final player = _player;
    if (player != null) {
      player.pause();
      try {
        await _collectListeningSamples(player);
        _listening.flush();
      } catch (_) {}
      await player.flush();
      if (!_isActive || epoch != _outputEpoch || !identical(player, _player)) {
        return;
      }
    }
    _baseOffsetMs = ms;
    _queuedToPlayerSamples = 0;
    _playedSamples = 0;
    _startedPlayback = false;
    _reportedStart = false;
    _startupBufferFilled = false;
    _autoPaused = false;
    _paused = _userPaused;
    _pumpSuspended = false;
  }

  void _requestRemoteRange(int ms, {required bool continuation}) {
    final quic = _quic;
    if (quic == null || !_isActive) return;
    _rawReader.reset();
    _incomingSegment = null;
    _incomingStartMs = ms;
    _incomingRangeEndMs = null;
    _incomingEndOfTrack = true;
    _remoteContinuation = continuation;
    _pendingSeekMs = ms;
    _pendingSeekId = _allocateSeekId();
    _waitingForHeader = true;
    try {
      _transportRequestId = quic.seek(
        trackId: trackId,
        positionMs: ms,
        seekId: _pendingSeekId!,
      );
      _reportBuffer(force: true);
    } catch (error) {
      _waitingForHeader = false;
      _failSeek('error');
      throw Exception('Unable to request audio range: $error');
    }
  }

  int get _positionMs =>
      _baseOffsetMs +
      _playedSamples * 1000 ~/ math.max(1, _sampleRate * _channels);

  void _reportBuffer({bool force = false, bool suspended = false}) {
    final quic = _quic;
    if (quic == null || !_serverBackpressureEnabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetMs = _userPaused ? 2000 : (_isLoopbackHost ? 3000 : 8000);
    final bufferedMs = suspended
        ? targetMs
        : _waitingForHeader
        ? 0
        : _encodedCache.bufferedAheadMs(_positionMs);
    // Refresh below the server's stale-report deadline; avoid per-tick chatter.
    if (!force &&
        now - _lastBufferReportAtMs < 1000 &&
        (bufferedMs - _lastReportedBufferMs).abs() < 500 &&
        targetMs == _lastReportedTargetMs) {
      return;
    }
    _lastBufferReportAtMs = now;
    _lastReportedBufferMs = bufferedMs;
    _lastReportedTargetMs = targetMs;
    quic.sendBufferStats(bufferMs: bufferedMs, targetMs: targetMs, force: true);
  }

  int _allocateSeekId() {
    _nextSeekId = (_nextSeekId + 1) & 0x7fffffff;
    if (_nextSeekId == 0) {
      _nextSeekId = 1;
    }
    return _nextSeekId;
  }

  void _configureBufferProfile(String host) {
    _isLoopbackHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    _networkProfileLevel = 0;
    _stableBufferTicks = 0;
    _lastObservedRttMs = null;
    _applyBufferProfile(log: true);
  }

  void _configureLocalBufferProfile() {
    _isLoopbackHost = true;
    _networkProfileLevel = 0;
    _stableBufferTicks = 0;
    _lastObservedRttMs = null;
    _applyBufferProfile(log: true);
  }

  void _applyBufferProfile({bool log = false}) {
    double prebufferSeconds;
    double rebufferMinSeconds;
    double rebufferTargetSeconds;

    if (_isLoopbackHost) {
      prebufferSeconds = _prebufferSecondsLocal;
      rebufferMinSeconds = _rebufferMinSecondsLocal;
      rebufferTargetSeconds = _rebufferTargetSecondsLocal;
    } else {
      prebufferSeconds = 0.12;
      rebufferMinSeconds = 0.08;
      rebufferTargetSeconds = 0.3;
      if (_networkProfileLevel >= 1) {
        prebufferSeconds = math.max(prebufferSeconds, 0.2);
        rebufferMinSeconds = math.max(rebufferMinSeconds, 0.12);
        rebufferTargetSeconds = math.max(rebufferTargetSeconds, 0.5);
      }
      if (_networkProfileLevel >= 2) {
        prebufferSeconds = math.max(prebufferSeconds, 0.3);
        rebufferMinSeconds = math.max(rebufferMinSeconds, 0.2);
        rebufferTargetSeconds = math.max(rebufferTargetSeconds, 0.8);
      }
    }

    final changed =
        prebufferSeconds != _prebufferSeconds ||
        rebufferMinSeconds != _rebufferMinSeconds ||
        rebufferTargetSeconds != _rebufferTargetSeconds;

    _prebufferSeconds = prebufferSeconds;
    _rebufferMinSeconds = rebufferMinSeconds;
    _rebufferTargetSeconds = rebufferTargetSeconds;
    _refreshBufferTargets();

    if (log || changed) {
      _log(
        'Buffer profile: level=$_networkProfileLevel '
        'prebuffer=${_prebufferSeconds.toStringAsFixed(1)}s '
        'rebuffer_min=${_rebufferMinSeconds.toStringAsFixed(1)}s '
        'rebuffer_target=${_rebufferTargetSeconds.toStringAsFixed(1)}s'
        '${_lastObservedRttMs == null ? '' : ' rtt=${_lastObservedRttMs}ms'}',
      );
    }
  }

  void _refreshBufferTargets() {
    if (_sampleRate <= 0 || _channels <= 0) {
      return;
    }

    if (_quickStart) {
      var startSamples = _frameSamples * _channels;
      if (startSamples <= 0) {
        startSamples = (_sampleRate * _channels * _seekStartSeconds).round();
      }
      if (startSamples <= 0) {
        startSamples = 1;
      }
      _prebufferTargetSamples = startSamples;
      _rebufferMinSamples = (_sampleRate * _channels * _seekCatchupMinSeconds)
          .round();
      _rebufferTargetSamples =
          (_sampleRate * _channels * _seekCatchupTargetSeconds).round();
      _ensureBufferCapacity();
      return;
    }

    _prebufferTargetSamples = (_sampleRate * _channels * _prebufferSeconds)
        .round();
    _rebufferMinSamples = (_sampleRate * _channels * _rebufferMinSeconds)
        .round();
    _rebufferTargetSamples = (_sampleRate * _channels * _rebufferTargetSeconds)
        .round();
    _ensureBufferCapacity();
  }

  void _ensureBufferCapacity() {
    // Profiles can change during playback and after the short seek-start gate.
    // The refill target must fit, even while output is paused for buffering.
    final minimumSamples = math.max(
      math.max(_prebufferTargetSamples, _rebufferTargetSamples) * 2,
      _pumpChunkSamples * 4,
    );
    _buffer?.ensureCapacity(minimumSamples);
  }

  int _serverBufferTargetMs() {
    final targetSeconds = _quickStart
        ? _seekCatchupTargetSeconds
        : _rebufferTargetSeconds;
    // Backpressure must never stop delivery before the startup gate opens.
    final startupSeconds = !_startedPlayback ? _prebufferSeconds : 0.0;
    final targetMs = (math.max(targetSeconds, startupSeconds) * 1000).ceil();
    return targetMs > 0 ? targetMs : 1;
  }

  void _updateAdaptiveBufferProfile({required int bufferedMs, int? rttMs}) {
    _lastObservedRttMs = rttMs;
    if (_isLoopbackHost || _quickStart) {
      return;
    }

    var desiredLevel = _networkProfileLevel;
    if (rttMs != null) {
      if (rttMs >= 350) {
        desiredLevel = 2;
      } else if (rttMs >= 180 && desiredLevel < 1) {
        desiredLevel = 1;
      }
    }

    final stableEnough =
        !_autoPaused &&
        (rttMs == null || rttMs <= 120) &&
        bufferedMs >= (_rebufferTargetSeconds * 2000).round();
    if (stableEnough) {
      _stableBufferTicks += 1;
      if (_stableBufferTicks >= 20 && desiredLevel > 0) {
        desiredLevel -= 1;
        _stableBufferTicks = 0;
      }
    } else {
      _stableBufferTicks = 0;
    }

    if (desiredLevel != _networkProfileLevel) {
      _networkProfileLevel = desiredLevel;
      _applyBufferProfile(log: true);
    }
  }

  Future<void> run() async {
    var completed = false;
    try {
      await _runPlayback();
      completed = _isActive;
    } catch (err) {
      _log('Playback failed: $err');
      final rejected = err is _AudioSourceRejected;
      _sendPlaybackMessage({
        'type': 'state',
        'active': false,
        'paused': false,
        if (rejected) 'source_rejected': true,
      });
      if (rejected) _failSeek('source_rejected');
    } finally {
      if (_stopCompletion != null) await _stopCompletion;
      _listening.flush(endReason: completed ? 'finished' : 'interrupted');
      _stopStats();
      _decoder?.dispose();
      _decoder = null;
      _localDecoder?.close();
      _localDecoder = null;
      _player?.dispose();
      _player = null;
      _playerSampleRate = null;
      _playerChannels = null;
      _playerDeviceId = null;
      final connection = _quic;
      if (completed && connection != null && _releaseConnection != null) {
        _releaseConnection(connection);
      } else {
        connection?.close();
      }
      _quic = null;
    }
  }

  Future<void> _runLocalFilePlayback(String filePath) async {
    _configureLocalBufferProfile();
    _log('Opening local audio file: $filePath');
    final decoder = LocalAudioDecoder.open(filePath, startOffset: startOffset);
    _localDecoder = decoder;

    _sampleRate = decoder.sampleRate;
    _channels = decoder.channels;
    _baseOffsetMs = startOffset.inMilliseconds;
    _quickStart = quickStart && startOffset.inMilliseconds > 0;
    _log(
      'Local decoder: $_sampleRate Hz, ${_channels}ch, duration=${decoder.duration.inMilliseconds} ms',
    );
    await _createLocalPcmOutput();
    _startStats();

    Future<void>? pumpTask;
    if (!_pumpRunning) {
      pumpTask = _runPump();
    }

    final readSamples = math.max(
      _channels,
      ((_sampleRate * _channels * 200) / 1000).round(),
    );
    final alignedReadSamples = readSamples - (readSamples % _channels);
    final readBuffer = Int16List(
      alignedReadSamples > 0 ? alignedReadSamples : _channels,
    );

    while (_isActive) {
      final pendingSeekMs = _pendingSeekMs;
      if (pendingSeekMs != null) {
        await _applyLocalSeek(decoder, pendingSeekMs);
        continue;
      }

      if (!_pumpRunning) pumpTask = _runPump();
      if (_streamEnded) {
        if (_autoPaused && !_userPaused) _resumeFromAutoPause();
        if (!_paused && (_buffer?.length ?? 0) == 0) {
          final generation = _seekRequestGeneration;
          final epoch = _outputEpoch;
          final player = _player!;
          final idle = await player.isIdle();
          if (!_isActive ||
              generation != _seekRequestGeneration ||
              epoch != _outputEpoch ||
              !identical(player, _player)) {
            continue;
          }
          if (idle && !_paused && (_buffer?.length ?? 0) == 0) break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }

      final buffer = _buffer;
      if (buffer != null && !_streamEnded) {
        final minFree = _pumpChunkSamples > 0 ? _pumpChunkSamples : _channels;
        if (buffer.free < minFree) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
      }

      final read = decoder.readInto(readBuffer);
      if (read == 0) {
        _streamEnded = true;
        continue;
      }
      await _writeToBuffer(Int16List.fromList(readBuffer.sublist(0, read)));
    }

    _streamEnded = true;
    _log('Local file ended.');
    if (_autoPaused && !_userPaused) {
      _resumeFromAutoPause();
    }
    if (pumpTask != null) {
      await pumpTask;
    }
    if (_isActive) {
      _listening.flush(endReason: 'finished');
      _sendPlaybackMessage({'type': 'complete'});
    }
  }

  Future<void> _applyLocalSeek(
    LocalAudioDecoder decoder,
    int requestedMs,
  ) async {
    final seekId = _allocateSeekId();
    final requestGeneration = _seekRequestGeneration;
    // Container seeking needs a position inside the final packet. FLAC can
    // reject an exact EOF timestamp before the pump can acknowledge readiness.
    final durationMs = decoder.duration.inMilliseconds;
    final targetMs = math.max(
      0,
      durationMs > 0 ? math.min(requestedMs, durationMs - 1) : requestedMs,
    );
    await _resetOutputForSeek(targetMs);
    if (!_isActive || requestGeneration != _seekRequestGeneration) return;
    _pendingSeekMs = null;
    _pendingSeekId = null;
    _activeSeekId = seekId;
    final actual = decoder.seek(Duration(milliseconds: targetMs));
    if (!_isActive) {
      return;
    }
    _baseOffsetMs = actual.inMilliseconds;
    final requestedAtMs = _pendingSeekRequestedAtMs;
    if (requestedAtMs != null) {
      final latencyMs = DateTime.now().millisecondsSinceEpoch - requestedAtMs;
      _log('Local seek accepted after ${latencyMs}ms (seek_id=$seekId).');
    }
    _pendingSeekRequestedAtMs = null;
    await _createLocalPcmOutput();
    _pumpSuspended = false;
  }

  Future<void> _createLocalPcmOutput() async {
    _frameSamples = (_sampleRate * 20 / 1000).round();
    _pumpChunkSamples = ((_sampleRate * _channels * _pumpChunkMs) / 1000)
        .round();
    if (_pumpChunkSamples <= 0) {
      _pumpChunkSamples = math.max(1, _frameSamples * _channels);
    }
    _refreshBufferTargets();

    final targetSeconds = _quickStart
        ? _seekCatchupTargetSeconds
        : (_prebufferSeconds > _rebufferTargetSeconds
              ? _prebufferSeconds
              : _rebufferTargetSeconds);
    final capacitySamples = (targetSeconds * 4.0 * _sampleRate * _channels)
        .round();
    final minCapacitySamples = _rebufferTargetSamples * 2;
    var finalCapacity = capacitySamples;
    if (minCapacitySamples > finalCapacity) {
      finalCapacity = minCapacitySamples;
    }
    final minPumpCapacity = _pumpChunkSamples * 4;
    if (minPumpCapacity > finalCapacity) {
      finalCapacity = minPumpCapacity;
    }
    _buffer = PcmRingBuffer(finalCapacity);

    if (_player == null ||
        _playerSampleRate != _sampleRate ||
        _playerChannels != _channels ||
        _playerDeviceId != _outputDeviceId) {
      final epoch = ++_outputEpoch;
      final previous = _player;
      _player = null;
      if (previous != null) await _disposeReplacedOutput(previous);
      if (!_isActive || epoch != _outputEpoch) return;
      _player =
          _outputFactory?.call(_sampleRate, _channels, _outputDeviceId) ??
          _createPlayer(
            sampleRate: _sampleRate,
            channels: _channels,
            deviceId: _outputDeviceId,
          );
      _playerSampleRate = _sampleRate;
      _playerChannels = _channels;
      _playerDeviceId = _outputDeviceId;
    }
    _player!.setVolume(_volume);
    if (_paused) _player!.pause();
    _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': _paused});
  }

  Future<void> _runPlayback() async {
    if (!(Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isAndroid)) {
      throw Exception('Audio output is unavailable on this platform.');
    }
    _baseOffsetMs = startOffset.inMilliseconds;
    _queuedToPlayerSamples = 0;
    _playedSamples = 0;
    _bytesReceived = 0;
    _lastBitrateBytes = 0;
    _reportedStart = false;
    _startedPlayback = false;
    _startupBufferFilled = false;
    _streamEnded = false;
    _quickStart = quickStart && startOffset.inMilliseconds > 0;
    final localPath = localFilePath;
    if (localPath != null) {
      await _runLocalFilePlayback(localPath);
      return;
    }
    final uri = Uri.parse(baseUrl);
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    _configureBufferProfile(host);
    final httpPort = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final port = quicPort != null && quicPort! > 0 ? quicPort! : httpPort + 1;
    var quic =
        _quic ??
        QuicClient.connect(
          host: host == 'localhost' ? '127.0.0.1' : host,
          port: port,
          token: token,
          serverPin: serverPin,
        );
    _quic = quic;
    try {
      _transportRequestId = quic.openTrack(
        trackId: trackId,
        mode: settings.mode,
        quality: settings.quality,
        frameMs: settings.frameMs,
        queue: queueTrackIds,
        startMs: startOffset.inMilliseconds,
      );
    } catch (_) {
      quic.close();
      quic = QuicClient.connect(
        host: host,
        port: port,
        token: token,
        serverPin: serverPin,
      );
      _quic = quic;
      _transportRequestId = quic.openTrack(
        trackId: trackId,
        mode: settings.mode,
        quality: settings.quality,
        frameMs: settings.frameMs,
        queue: queueTrackIds,
        startMs: startOffset.inMilliseconds,
      );
    }
    _incomingStartMs = startOffset.inMilliseconds;
    _waitingForHeader = true;
    _startStats();
    // Receive/cache and decode/output are independent asynchronous loops. A
    // paused or full PCM queue cannot prevent a new range header from arriving.
    final receiveTask = _receiveRemoteAudio(quic);
    final decodeTask = _decodeRemoteAudio();
    try {
      await Future.wait([receiveTask, decodeTask], eagerError: true);
    } catch (_) {
      requestStop(outcome: 'error');
      rethrow;
    }
    if (_isActive) {
      _listening.flush(endReason: 'finished');
      _sendPlaybackMessage({'type': 'complete'});
    }
  }

  void _pollTransportEvents(QuicClient quic) {
    Map<String, Object?>? event;
    while ((event = quic.pollEvent()) != null) {
      final requestId = (event!['request_id'] as num?)?.toInt();
      if (requestId != null && requestId != _transportRequestId) continue;
      if (event['type'] == 'error') {
        final message = 'Audio range request failed: ${event['message']}';
        if (event['origin'] == 'server') throw _AudioSourceRejected(message);
        _failSeek('server_error');
        throw Exception(message);
      }
      if (event['type'] != 'stream') continue;
      final version = event['source_version']?.toString() ?? '';
      if (_sourceVersion.isNotEmpty &&
          version.isNotEmpty &&
          _sourceVersion != version) {
        throw Exception('The audio source changed during playback.');
      }
      _sourceVersion = version;
      _incomingStartMs =
          (event['position_ms'] as num?)?.toInt() ?? _incomingStartMs;
      _incomingRangeEndMs = (event['range_end_ms'] as num?)?.toInt();
      _incomingEndOfTrack = event['end_of_track'] != false;
    }
  }

  Future<void> _receiveRemoteAudio(QuicClient quic) async {
    final data = Uint8List(64 * 1024);
    while (_isActive && !_remotePlaybackComplete) {
      _pollTransportEvents(quic);
      if (_streamEnded && !_waitingForHeader) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      final segment = _incomingSegment;
      final cursor = _decodeCursor;
      if (!_waitingForHeader &&
          segment != null &&
          segment.complete &&
          !segment.endOfTrack &&
          cursor != null &&
          segment.rangeEndMs - _positionMs <= (_userPaused ? 2000 : 8000)) {
        final next = _encodedCache.seek(segment.rangeEndMs);
        if (next == null) {
          _requestRemoteRange(segment.rangeEndMs, continuation: true);
        }
      }
      // Limit encoded read-ahead by playback time, independently of PCM space.
      // Control events are still consumed every iteration, including while paused.
      final ahead = _encodedCache.bufferedAheadMs(_positionMs);
      final horizon = _userPaused ? 2000 : (_isLoopbackHost ? 3000 : 8000);
      if (!_waitingForHeader && ahead >= horizon + 1000) {
        _reportBuffer();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      final read = quic.read(data);
      _pollTransportEvents(quic);
      if (read == -5) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      if (read <= 0) {
        throw Exception(
          'QUIC audio connection failed: ${quic.lastError() ?? read}',
        );
      }
      _bytesReceived += read;
      for (final event in _rawReader.add(
        Uint8List.sublistView(data, 0, read),
      )) {
        if (event is RawOpusSeekMarker) {
          if (_pendingSeekId != event.seekId) {
            throw Exception('Unexpected audio seek generation.');
          }
          _activeSeekId = event.seekId;
          _pendingSeekId = null;
        } else if (event is RawOpusStreamHeader) {
          final headerTrack = _extractHeaderTrackId(event.bytes);
          if (headerTrack != null && headerTrack != trackId) {
            throw Exception('Audio range belongs to a different track.');
          }
          final header = event.header;
          final incoming = EncodedAudioSegment(
            header: header,
            startMs: _incomingStartMs,
            rangeEndMs: _incomingRangeEndMs ?? header.durationMs,
            endOfTrack: _incomingEndOfTrack,
            sourceVersion: _sourceVersion,
          );
          if (!_encodedCache.addSegment(
            incoming,
            pinned: _decodeCursor?.segment,
          )) {
            throw Exception('Encoded audio cache exceeded its memory budget.');
          }
          _incomingSegment = incoming;
          _waitingForHeader = false;
          _pendingSeekMs = null;
          if (!_remoteContinuation && _decodeCursor == null) {
            _decodeCursor = incoming.cursorAt(incoming.startMs);
          }
        } else if (event is RawOpusPacket) {
          final incoming = _incomingSegment;
          if (incoming == null) {
            throw Exception('Audio packet without a range header.');
          }
          if (!_encodedCache.append(
            incoming,
            event.bytes,
            pinned: _decodeCursor?.segment,
          )) {
            throw Exception('Encoded audio cache exceeded its memory budget.');
          }
        } else if (event is RawOpusEnd) {
          final incoming = _incomingSegment;
          if (incoming == null) {
            throw Exception('Audio range ended before its header.');
          }
          incoming.complete = true;
        }
      }
      _reportBuffer();
    }
  }

  Future<void> _configureRemoteOutput(
    RawOpusHeader header, {
    required int generation,
    required EncodedAudioCursor cursor,
  }) async {
    final reset = _outputReset;
    if (reset != null) {
      await reset;
      if (identical(reset, _outputReset)) _outputReset = null;
    }
    if (!_isActive ||
        generation != _seekRequestGeneration ||
        !identical(cursor, _decodeCursor)) {
      return;
    }
    _sampleRate = header.sampleRate;
    _channels = header.channels;
    _frameSamples = _sampleRate * header.frameMs ~/ 1000;
    _pumpChunkSamples = _sampleRate * _channels * _pumpChunkMs ~/ 1000;
    _refreshBufferTargets();
    _buffer ??= PcmRingBuffer(
      math.max(_sampleRate * _channels, _rebufferTargetSamples * 2),
    );
    _ensureBufferCapacity();
    if (_player == null ||
        _playerSampleRate != _sampleRate ||
        _playerChannels != _channels ||
        _playerDeviceId != _outputDeviceId) {
      final epoch = ++_outputEpoch;
      final previous = _player;
      _player = null;
      if (previous != null) await _disposeReplacedOutput(previous);
      if (!_isActive || epoch != _outputEpoch) return;
      _player =
          _outputFactory?.call(_sampleRate, _channels, _outputDeviceId) ??
          _createPlayer(
            sampleRate: _sampleRate,
            channels: _channels,
            deviceId: _outputDeviceId,
          );
      _playerSampleRate = _sampleRate;
      _playerChannels = _channels;
      _playerDeviceId = _outputDeviceId;
    }
    _player!.setVolume(_volume);
    if (_paused) _player!.pause();
    _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': _paused});
  }

  Future<void> _decodeRemoteAudio() async {
    EncodedAudioCursor? configured;
    int configuredGeneration = -1;
    Future<void>? pump;
    try {
      while (_isActive) {
        final cachedSeek = _cachedSeek;
        if (cachedSeek != null) {
          _cachedSeek = null;
          _decodeCursor = cachedSeek;
        }
        final cursor = _decodeCursor;
        if (cursor == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        final generation = _seekRequestGeneration;
        if (!identical(cursor, configured) ||
            generation != configuredGeneration) {
          _decoder?.dispose();
          _decoder = null;
          await _configureRemoteOutput(
            cursor.segment.header,
            generation: generation,
            cursor: cursor,
          );
          if (!_isActive ||
              generation != _seekRequestGeneration ||
              !identical(cursor, _decodeCursor)) {
            continue;
          }
          if (generation != configuredGeneration) {
            // Use the server's accepted position (including endpoint clamping).
            _baseOffsetMs = cursor.positionMs;
            _decodedThroughSample = cursor.positionMs * _sampleRate ~/ 1000;
          }
          _decoder =
              _decoderFactory?.call(_sampleRate, _channels) ??
              OpusDecoder(sampleRate: _sampleRate, channels: _channels);
          configured = cursor;
          configuredGeneration = generation;
          if (!_pumpRunning) pump = _runPump();
        }
        if (_player != null && _buffer != null && !_pumpRunning) {
          pump = _runPump();
        }
        final segment = cursor.segment;
        if (cursor.packetIndex >= segment.packets.length) {
          final atEnd =
              segment.complete && segment.availableEndMs >= segment.rangeEndMs;
          if (atEnd && segment.endOfTrack) {
            _streamEnded = true;
            if (_autoPaused && !_userPaused) _resumeFromAutoPause();
            if (!_paused && (_buffer?.length ?? 0) == 0) {
              final player = _player!;
              final epoch = _outputEpoch;
              final idle = await player.isIdle();
              if (!_isActive ||
                  generation != _seekRequestGeneration ||
                  epoch != _outputEpoch ||
                  !identical(cursor, _decodeCursor) ||
                  !identical(player, _player)) {
                continue;
              }
              if (idle && !_paused && (_buffer?.length ?? 0) == 0) {
                _remotePlaybackComplete = true;
                break;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
            continue;
          }
          if (segment.complete && !atEnd) {
            throw Exception(
              'Encoded audio range ended before its advertised boundary.',
            );
          }
          final nextMs = atEnd ? segment.rangeEndMs : segment.availableEndMs;
          final next = _encodedCache.seek(nextMs);
          if (next != null && !identical(next.segment, segment)) {
            // Range requests use milliseconds, but an incomplete packet cache
            // can finish between milliseconds. Drop any overlap already queued.
            final overlap = math.max(
              0,
              (_decodedThroughSample ?? 0) - nextMs * _sampleRate ~/ 1000,
            );
            next.skipSamplesPerChannel += overlap;
            _decodeCursor = next;
            continue;
          }
          final incoming = _incomingSegment;
          // A retained partial range may have been abandoned by an earlier seek.
          // Wait only for its live producer or a replacement covering the gap;
          // a replacement header can arrive before its first audio packet.
          final receivingMissingAudio =
              incoming != null &&
              !incoming.complete &&
              (identical(incoming, segment) ||
                  (incoming.startMs <= nextMs && nextMs < incoming.rangeEndMs));
          if (!_waitingForHeader && !receivingMissingAudio) {
            _requestRemoteRange(nextMs, continuation: true);
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        final packet = segment.packets[cursor.packetIndex];
        var samples = _decoder!.decode(
          packet,
          frameSize: segment.header.sampleRate * segment.header.frameMs ~/ 1000,
        );
        cursor.packetIndex++;
        final skip = math.min(
          samples.length,
          cursor.skipSamplesPerChannel * _channels,
        );
        cursor.skipSamplesPerChannel -= skip ~/ _channels;
        if (skip > 0) samples = samples.sublist(skip);
        final endSamples =
            (segment.rangeEndMs - segment.startMs) * _sampleRate ~/ 1000;
        final packetEndSamples =
            cursor.packetIndex * segment.frameSamples - segment.header.preSkip;
        final excessSamples =
            math.max(0, packetEndSamples - endSamples) * _channels;
        if (excessSamples > 0) {
          samples = samples.sublist(
            0,
            math.max(0, samples.length - excessSamples),
          );
        }
        cursor.positionMs = math.min(
          segment.rangeEndMs,
          segment.startMs + math.max(0, packetEndSamples) * 1000 ~/ _sampleRate,
        );
        if (samples.isNotEmpty) await _writeToBuffer(samples);
        if (generation != _seekRequestGeneration) continue;
        _decodedThroughSample = math.max(
          _decodedThroughSample ?? 0,
          segment.startMs * _sampleRate ~/ 1000 +
              math.min(math.max(0, packetEndSamples), endSamples),
        );
      }
      if (pump != null) await pump;
    } catch (_) {
      requestStop(outcome: 'decode_error');
      rethrow;
    }
  }

  Future<void> _runPump() async {
    _pumpRunning = true;
    try {
      while (_isActive) {
        final player = _player;
        final buffer = _buffer;
        if (player == null || buffer == null || _pumpSuspended) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        if (!_startedPlayback) {
          if (buffer.length == 0 && _streamEnded) {
            _markSeekReady();
            return;
          }
          if (!_streamEnded && buffer.length < _prebufferTargetSamples) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            continue;
          }
          _startedPlayback = true;
          _markSeekReady();
          if (!_paused) player.resume();
          _reportStarted();
        }
        if (_paused) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        final chunk = buffer.read(_pumpChunkSamples);
        if (chunk == null || chunk.isEmpty) {
          if (_streamEnded) {
            await _drainPlayer(player);
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
        if (_pumpSuspended ||
            !identical(player, _player) ||
            !identical(buffer, _buffer)) {
          continue;
        }
        final epoch = _outputEpoch;
        try {
          await _writeSamples(player, chunk);
        } catch (error) {
          if (!_isActive) return;
          if (epoch != _outputEpoch || !identical(player, _player)) continue;
          rethrow;
        }
      }
    } catch (error) {
      if (_isActive) {
        _log('Audio output failed: $error');
        requestStop(outcome: 'output_error');
        _sendPlaybackMessage({
          'type': 'state',
          'active': false,
          'paused': false,
        });
      }
    } finally {
      _pumpRunning = false;
    }
  }

  Future<void> _writeToBuffer(Int16List samples) async {
    final buffer = _buffer;
    if (buffer == null) {
      return;
    }
    final epoch = _outputEpoch;
    final generation = _seekRequestGeneration;
    var offset = 0;
    while (offset < samples.length &&
        _isActive &&
        epoch == _outputEpoch &&
        generation == _seekRequestGeneration &&
        identical(buffer, _buffer)) {
      final written = buffer.write(samples, offset);
      if (written == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      offset += written;
    }
  }

  Future<void> _writeSamples(
    _NativeAudioPlayer player,
    Int16List samples,
  ) async {
    final epoch = _outputEpoch;
    await player.write(samples);
    if (epoch != _outputEpoch || !identical(player, _player)) {
      return;
    }
    _queuedToPlayerSamples += samples.length;
  }

  Future<void> _drainPlayer(_NativeAudioPlayer player) async {
    final epoch = _outputEpoch;
    while (_isActive) {
      bool idle;
      try {
        final done = await _collectListeningSamples(player);
        if (epoch != _outputEpoch || !identical(player, _player)) return;
        _playedSamples += done;
        idle = await player.isIdle();
        if (epoch != _outputEpoch || !identical(player, _player)) return;
      } catch (_) {
        return;
      }
      if (idle) {
        try {
          final tail = await _collectListeningSamples(player);
          if (epoch == _outputEpoch && identical(player, _player)) {
            _playedSamples += tail;
          }
        } catch (_) {}
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!identical(player, _player)) {
        return;
      }
    }
  }

  void _reportStarted() {
    if (_reportedStart) {
      return;
    }
    _reportedStart = true;
    _quickStart = false;
    _refreshBufferTargets();
    final activeSeekId = _activeSeekId;
    if (activeSeekId != null) {
      _log('Seek audio resumed (seek_id=$activeSeekId).');
      _activeSeekId = null;
    }
    _log('Audio playback started.');
    _sendPlaybackMessage({'type': 'started'});
  }

  void _startStats() {
    _stopStats();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_collectAndSendStats());
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _statsCollectionInFlight = false;
  }

  Future<void> _collectAndSendStats() async {
    if (_statsCollectionInFlight) {
      return;
    }
    _statsCollectionInFlight = true;
    try {
      final player = _player;
      if (player != null) {
        final epoch = _outputEpoch;
        try {
          final done = await _collectListeningSamples(player);
          if (epoch != _outputEpoch || !identical(player, _player)) return;
          _playedSamples += done;
        } catch (_) {
          return;
        }
      }
      if (!_isActive) return;
      final buffer = _buffer;
      final bufferSamples = buffer?.length ?? 0;
      final queuedInPlayer = _queuedToPlayerSamples > _playedSamples
          ? (_queuedToPlayerSamples - _playedSamples)
          : 0;
      final bufferedSamples = bufferSamples + queuedInPlayer;
      final samplesPerSecond = _sampleRate * _channels;
      final bufferedMs = samplesPerSecond == 0
          ? 0
          : (bufferedSamples * 1000 ~/ samplesPerSecond);

      final quic = _quic;
      if (quic != null) {
        try {
          final stats = quic.pollStats();
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (stats != null &&
              nowMs - _lastQuicStatsLogAtMs >= _quicStatsLogIntervalMs) {
            _lastQuicStatsLogAtMs = nowMs;
            _log(stats);
          }
        } catch (_) {
          // Ignore stats poll failures.
        }
      }

      int? rttMs;
      if (quic != null) {
        try {
          rttMs = quic.pollRttMs();
        } catch (_) {
          // Ignore RTT poll failures.
        }
      }

      _updateAdaptiveBufferProfile(bufferedMs: bufferedMs, rttMs: rttMs);

      if (quic != null) {
        try {
          _reportBuffer();
        } catch (_) {}
      }

      final playedMs = samplesPerSecond == 0
          ? 0
          : (_playedSamples * 1000 ~/ samplesPerSecond);
      final position = Duration(milliseconds: _baseOffsetMs + playedMs);
      _maybeRebuffer(bufferedSamples);
      _sendPlaybackMessage({
        'type': 'stats',
        'position_ms': position.inMilliseconds,
        'buffered_ms': _isLocalFile
            ? bufferedMs
            : math.max(
                bufferedMs,
                _encodedCache.bufferedAheadMs(position.inMilliseconds),
              ),
        'bitrate_kbps': _isLocalFile ? null : _currentBitrateKbps(),
        'rtt_ms': _isLocalFile ? null : rttMs,
        'local': _isLocalFile,
      });
    } finally {
      _statsCollectionInFlight = false;
    }
  }

  double? _currentBitrateKbps() {
    final now = DateTime.now();
    final lastAt = _lastBitrateAt;
    if (lastAt == null) {
      _lastBitrateAt = now;
      _lastBitrateBytes = _bytesReceived;
      return null;
    }
    final deltaMs = now.difference(lastAt).inMilliseconds;
    if (deltaMs <= 0) {
      return null;
    }
    final deltaBytes = _bytesReceived - _lastBitrateBytes;
    if (deltaBytes <= 0) {
      return null;
    }
    _lastBitrateAt = now;
    _lastBitrateBytes = _bytesReceived;
    return (deltaBytes * 8.0) / deltaMs;
  }

  void _maybeRebuffer(int bufferedSamples) {
    if (_streamEnded) {
      if (_autoPaused && !_userPaused) {
        _resumeFromAutoPause();
      }
      return;
    }
    if (_userPaused || !_startedPlayback) {
      return;
    }
    // Let a short startup buffer grow without immediately auto-pausing.
    // Once enough audio has accumulated, use the steady-state thresholds.
    if (!_startupBufferFilled) {
      if (bufferedSamples >= _rebufferMinSamples) {
        _startupBufferFilled = true;
      } else if (bufferedSamples > _sampleRate * _channels ~/ 20) {
        return;
      }
    }
    if (!_autoPaused && bufferedSamples <= _rebufferMinSamples) {
      _stableBufferTicks = 0;
      if (!_quickStart && !_isLoopbackHost && _networkProfileLevel < 2) {
        _networkProfileLevel += 1;
        _applyBufferProfile(log: true);
      }
      _pauseForBuffer(bufferedSamples);
      return;
    }
    final resumeThresholdSamples = _reportedStart && _playedSamples == 0
        ? _rebufferMinSamples
        : _rebufferTargetSamples;
    if (_autoPaused && bufferedSamples >= resumeThresholdSamples) {
      _resumeFromAutoPause();
    }
  }

  int _bufferedAudioMs() {
    final samplesPerSecond = _sampleRate * _channels;
    if (samplesPerSecond <= 0) {
      return 0;
    }
    final bufferSamples = _buffer?.length ?? 0;
    final queuedInPlayer = _queuedToPlayerSamples > _playedSamples
        ? (_queuedToPlayerSamples - _playedSamples)
        : 0;
    return ((bufferSamples + queuedInPlayer) * 1000 ~/ samplesPerSecond);
  }

  void _pauseForBuffer(int bufferedSamples) {
    final player = _player;
    if (player == null) {
      return;
    }
    final samplesPerSecond = _sampleRate * _channels;
    final bufferedMs = samplesPerSecond <= 0
        ? 0
        : (bufferedSamples * 1000 ~/ samplesPerSecond);
    _log(
      'Buffer low: buffered=${bufferedMs}ms target=${_serverBufferTargetMs()}ms; refilling.',
    );
    player.pause();
    _listening.flush();
    _paused = true;
    _autoPaused = true;
    _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': true});
  }

  void _resumeFromAutoPause() {
    if (_userPaused) {
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    player.resume();
    _paused = false;
    _autoPaused = false;
    _log(
      'Buffer recovered: buffered=${_bufferedAudioMs()}ms target=${_serverBufferTargetMs()}ms.',
    );
    _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': false});
  }

  void _log(String message) {
    _sendPlaybackMessage({'type': 'message', 'text': message});
  }
}

/// Runs the production receiver/cache/decoder/pump with in-memory test adapters.
/// Construction never starts an isolate, device, socket, or server.
@visibleForTesting
class AudioPlaybackHarness {
  AudioPlaybackHarness.local({
    required String filePath,
    required AudioPcmOutput Function(int sampleRate, int channels, int deviceId)
    outputFactory,
    bool initialPaused = false,
    Duration startOffset = Duration.zero,
    Map<String, dynamic>? listeningContext,
  }) {
    _session = _PlaybackSession.local(
      send: (event) {
        messages.add(event);
        _events.add(event);
      },
      playbackId: 1,
      getPlaybackId: () => 1,
      trackId: 'track',
      trackTitle: 'Test',
      filePath: filePath,
      startOffset: startOffset,
      initialPaused: initialPaused,
      volume: 1,
      outputDeviceId: -1,
      outputFactory: outputFactory,
      listeningContext: listeningContext,
    );
  }

  AudioPlaybackHarness({
    required QuicClient transport,
    required OpusDecoder Function(int sampleRate, int channels) decoderFactory,
    required AudioPcmOutput Function(int sampleRate, int channels, int deviceId)
    outputFactory,
    bool initialPaused = false,
    Duration startOffset = Duration.zero,
    Map<String, dynamic>? listeningContext,
  }) {
    _session = _PlaybackSession.remote(
      reusableConnection: transport,
      releaseConnection: (_) {},
      send: (event) {
        messages.add(event);
        _events.add(event);
      },
      playbackId: 1,
      getPlaybackId: () => 1,
      trackId: 'track',
      trackTitle: 'Test',
      baseUrl: 'http://test.local:3000',
      token: '',
      quicPort: null,
      settings: const StreamSettings(mode: 'fixed', quality: 'high'),
      startOffset: startOffset,
      queueTrackIds: const [],
      quickStart: true,
      initialPaused: initialPaused,
      volume: 1,
      outputDeviceId: -1,
      decoderFactory: decoderFactory,
      outputFactory: outputFactory,
      listeningContext: listeningContext,
    );
  }

  late final _PlaybackSession _session;
  final messages = <Map<String, dynamic>>[];
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Future<void>? _run;
  int _requestId = 0;
  Stream<Map<String, dynamic>> get events => _events.stream;
  int get cachedBytes => _session._encodedCache.bytes;
  int cachedAheadMilliseconds(int positionMs) =>
      _session._encodedCache.bufferedAheadMs(positionMs);
  bool get paused => _session._paused;
  bool get autoPaused => _session._autoPaused;
  void start() {
    _run = _session.run();
  }

  Future<void> pause() => _session.pause();
  Future<void> configureListening(
    Map<String, dynamic>? context, {
    bool discardPending = true,
  }) => _session.configureListening(context, discardPending: discardPending);
  void resume() => _session.resume();

  Future<bool> seek(Duration position) async {
    final requestId = ++_requestId;
    final result = events.firstWhere(
      (event) =>
          event['request_id'] == requestId &&
          (event['type'] == 'seek_ready' || event['type'] == 'seek_failed'),
    );
    await _session.seekTo(position, requestId: requestId);
    return (await result.timeout(const Duration(seconds: 6)))['type'] ==
        'seek_ready';
  }

  Future<void> close() async {
    _session.requestStop();
    await _run;
    await _events.close();
  }
}

const List<int> _rawHeaderMagic = [79, 80, 85, 83, 82, 48, 49, 0];
const int _rawHeaderMinLen = 40;

bool _hasRawHeaderMagic(Uint8List prefix) {
  if (prefix.length < _rawHeaderMagic.length) {
    return false;
  }
  for (var i = 0; i < _rawHeaderMagic.length; i++) {
    if (prefix[i] != _rawHeaderMagic[i]) {
      return false;
    }
  }
  return true;
}

String? _extractHeaderTrackId(Uint8List headerBytes) {
  if (headerBytes.length < 12) {
    return null;
  }
  if (!_hasRawHeaderMagic(headerBytes)) {
    return null;
  }
  if (headerBytes[8] != 1) {
    return null;
  }
  final headerLen = headerBytes[10] | (headerBytes[11] << 8);
  if (headerLen < _rawHeaderMinLen) {
    return null;
  }
  if (headerBytes.length < headerLen) {
    return null;
  }
  var idx = 12;
  if (idx + 4 + 1 + 1 + 4 + 4 + 2 + 2 * 6 > headerLen) {
    return null;
  }
  idx += 4; // sampleRate
  idx += 1; // channels
  idx += 1; // frameMs
  idx += 4; // bitrate
  idx += 4; // duration
  idx += 2; // preSkip
  final trackIdLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final titleLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final artistLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final albumLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final codecLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final containerLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;
  final totalLen =
      trackIdLen + titleLen + artistLen + albumLen + codecLen + containerLen;
  if (idx + totalLen > headerLen) {
    return null;
  }
  if (trackIdLen == 0) {
    return null;
  }
  final end = idx + trackIdLen;
  if (end > headerBytes.length) {
    return null;
  }
  return utf8.decode(headerBytes.sublist(idx, end), allowMalformed: true);
}

class _AudioWorkerInit {
  _AudioWorkerInit(this.sendPort, this.rootIsolateToken);

  final SendPort sendPort;
  final RootIsolateToken? rootIsolateToken;
}

void _audioWorkerMain(_AudioWorkerInit init) {
  final token = init.rootIsolateToken;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final receivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
  IsolateNameServer.registerPortWithName(
    receivePort.sendPort,
    _audioWorkerPortName,
  );
  init.sendPort.send(receivePort.sendPort);
  final engine = _AudioWorkerEngine(
    send: (message) {
      init.sendPort.send(message);
    },
  );

  receivePort.listen((message) async {
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
        final queue = rawQueue is List
            ? rawQueue.map((item) => item.toString()).toList()
            : const <String>[];
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
          startOffset: Duration(
            milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0,
          ),
          queueTrackIds: queue,
          quickStart: message['quick_start'] != false,
          initialPaused: message['initial_paused'] == true,
          listeningContext: context is Map
              ? Map<String, dynamic>.from(context)
              : null,
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
          startOffset: Duration(
            milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0,
          ),
          initialPaused: message['initial_paused'] == true,
          listeningContext: context is Map
              ? Map<String, dynamic>.from(context)
              : null,
        );
        break;
      case 'stop':
        await engine.stop();
        init.sendPort.send({
          'type': 'listening_flushed',
          'flush_request_id': message['flush_request_id'],
        });
        break;
      case 'pause':
        await engine.pause(
          playbackId: (message['playback_id'] as num?)?.toInt(),
        );
        break;
      case 'resume':
        engine.resume(playbackId: (message['playback_id'] as num?)?.toInt());
        break;
      case 'volume':
        final value = (message['value'] as num?)?.toDouble() ?? 1.0;
        engine.setVolume(value);
        break;
      case 'device':
        final deviceId =
            (message['device_id'] as num?)?.toInt() ?? kDefaultOutputDeviceId;
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
        receivePort.close();
        Isolate.exit();
      default:
        break;
    }
  });
}

typedef _NativeAudioPlayer = AudioPcmOutput;

/// Small, cancellable device queue. flush invalidates every pending write.
abstract class AudioPcmOutput {
  Future<void> write(Int16List samples);
  Future<void> flush();
  void dispose();
  void setVolume(double value);
  void pause();
  void resume();
  Future<int> collectDoneSamples();
  Future<bool> isIdle();
}

_NativeAudioPlayer _createPlayer({
  required int sampleRate,
  required int channels,
  required int deviceId,
}) {
  if (Platform.isWindows) {
    return _WaveOutPlayer(
      sampleRate: sampleRate,
      channels: channels,
      deviceId: deviceId,
    );
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return _CoreAudioPlayer(
      sampleRate: sampleRate,
      channels: channels,
      deviceId: deviceId,
    );
  }
  if (Platform.isAndroid) {
    return _AndroidChannelPlayer(
      sampleRate: sampleRate,
      channels: channels,
      deviceId: deviceId,
    );
  }
  throw Exception(
    'Audio playback is only implemented for Windows, Apple platforms, and Android right now.',
  );
}

class _AndroidChannelPlayer implements _NativeAudioPlayer {
  _AndroidChannelPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _deviceId = deviceId {
    _openFuture = _open();
  }

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  int? _handleId;
  late final Future<void> _openFuture;
  double _pendingVolume = 1.0;
  bool _pendingPaused = false;
  bool _disposed = false;
  int _writeEpoch = 0;

  Future<void> _open() async {
    final handle = await _androidAudioOutputChannel.invokeMethod<int>('open', {
      'sampleRate': _sampleRate,
      'channels': _channels,
      'deviceId': _deviceId,
    });
    if (handle == null || handle <= 0) {
      throw Exception('Android audio output open failed.');
    }
    if (_disposed) {
      await _androidAudioOutputChannel.invokeMethod<void>('close', {
        'id': handle,
      });
      return;
    }
    _handleId = handle;
    await _androidAudioOutputChannel.invokeMethod<void>('setVolume', {
      'id': handle,
      'value': _pendingVolume,
    });
    if (_pendingPaused) {
      await _androidAudioOutputChannel.invokeMethod<void>('pause', {
        'id': handle,
      });
    }
  }

  Future<int?> _handle() async {
    await _openFuture;
    return _handleId;
  }

  @override
  Future<void> write(Int16List samples) async {
    if (samples.isEmpty) {
      return;
    }
    final epoch = _writeEpoch;
    final handle = await _handle();
    if (handle == null) {
      return;
    }
    final bytes = Uint8List.view(
      samples.buffer,
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    while (true) {
      if (_disposed || epoch != _writeEpoch || handle != _handleId) return;
      final result = await _androidAudioOutputChannel.invokeMethod<int>(
        'write',
        {'id': handle, 'pcm': bytes},
      );
      if (_disposed || epoch != _writeEpoch || handle != _handleId) return;
      if (result == null || result == 0) {
        return;
      }
      if (result == _coreAudioQueueFull) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        continue;
      }
      throw Exception('Android audio write failed: $result');
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;
    final handle = await _handle();
    if (handle == null) {
      return;
    }
    await _androidAudioOutputChannel.invokeMethod<void>('flush', {
      'id': handle,
    });
  }

  @override
  void dispose() {
    _writeEpoch++;
    _disposed = true;
    final handle = _handleId;
    _handleId = null;
    if (handle != null) {
      _androidAudioOutputChannel.invokeMethod<void>('close', {'id': handle});
      return;
    }
    unawaited(
      _openFuture
          .then((_) {
            final openedHandle = _handleId;
            _handleId = null;
            if (openedHandle != null) {
              return _androidAudioOutputChannel.invokeMethod<void>('close', {
                'id': openedHandle,
              });
            }
            return Future<void>.value();
          })
          .catchError((_) {}),
    );
  }

  @override
  void setVolume(double value) {
    _pendingVolume = value.clamp(0.0, 1.0);
    final handle = _handleId;
    if (handle == null) {
      return;
    }
    _androidAudioOutputChannel.invokeMethod<void>('setVolume', {
      'id': handle,
      'value': _pendingVolume,
    });
  }

  @override
  void pause() {
    _pendingPaused = true;
    final handle = _handleId;
    if (handle == null) {
      return;
    }
    _androidAudioOutputChannel.invokeMethod<void>('pause', {'id': handle});
  }

  @override
  void resume() {
    _pendingPaused = false;
    final handle = _handleId;
    if (handle == null) {
      return;
    }
    _androidAudioOutputChannel.invokeMethod<void>('resume', {'id': handle});
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handleId;
    if (handle == null) {
      return 0;
    }
    final result = await _androidAudioOutputChannel.invokeMethod<int>(
      'collectDoneSamples',
      {'id': handle},
    );
    return result ?? 0;
  }

  @override
  Future<bool> isIdle() async {
    final handle = _handleId;
    if (handle == null) {
      return true;
    }
    final result = await _androidAudioOutputChannel.invokeMethod<bool>(
      'isIdle',
      {'id': handle},
    );
    return result ?? true;
  }
}

class _WaveOutPlayer implements _NativeAudioPlayer {
  _WaveOutPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _deviceId = deviceId {
    _open();
  }

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  ffi.Pointer<ffi.Pointer<ffi.Void>>? _handle;
  final List<_WaveBuffer> _inFlight = [];
  static const int _maxInFlight = 5;
  int _completedSamples = 0;
  int _writeEpoch = 0;

  void _open() {
    final handle = calloc<ffi.Pointer<ffi.Void>>();
    final format = calloc<WAVEFORMATEX>();
    format.ref.wFormatTag = WAVE_FORMAT_PCM;
    format.ref.nChannels = _channels;
    format.ref.nSamplesPerSec = _sampleRate;
    format.ref.wBitsPerSample = 16;
    format.ref.nBlockAlign = (_channels * 2);
    format.ref.nAvgBytesPerSec =
        format.ref.nSamplesPerSec * format.ref.nBlockAlign;
    format.ref.cbSize = 0;

    final deviceId = _deviceId == kDefaultOutputDeviceId
        ? WAVE_MAPPER
        : _deviceId;
    final result = _WaveOutBindings().waveOutOpen(
      handle,
      deviceId,
      format,
      ffi.nullptr,
      ffi.nullptr,
      CALLBACK_NULL,
    );
    calloc.free(format);
    if (result != MMSYSERR_NOERROR) {
      calloc.free(handle);
      throw Exception('waveOutOpen failed: $result');
    }
    _handle = handle;
  }

  @override
  Future<void> write(Int16List samples) async {
    final handle = _handle;
    final epoch = _writeEpoch;
    if (handle == null) {
      return;
    }

    final dataPtr = calloc<ffi.Int16>(samples.length);
    dataPtr.asTypedList(samples.length).setAll(0, samples);

    final header = calloc<WAVEHDR>();
    header.ref.lpData = dataPtr.cast<ffi.Uint8>();
    header.ref.dwBufferLength = samples.length * 2;
    header.ref.dwBytesRecorded = 0;
    header.ref.dwUser = 0;
    header.ref.dwFlags = 0;
    header.ref.dwLoops = 0;
    header.ref.lpNext = ffi.nullptr;
    header.ref.reserved = 0;

    final bindings = _WaveOutBindings();
    var result = bindings.waveOutPrepareHeader(
      handle.value,
      header,
      ffi.sizeOf<WAVEHDR>(),
    );
    if (result != MMSYSERR_NOERROR) {
      calloc.free(header);
      calloc.free(dataPtr);
      throw Exception('waveOutPrepareHeader failed: $result');
    }

    result = bindings.waveOutWrite(handle.value, header, ffi.sizeOf<WAVEHDR>());
    if (result != MMSYSERR_NOERROR) {
      bindings.waveOutUnprepareHeader(
        handle.value,
        header,
        ffi.sizeOf<WAVEHDR>(),
      );
      calloc.free(header);
      calloc.free(dataPtr);
      throw Exception('waveOutWrite failed: $result');
    }

    _inFlight.add(
      _WaveBuffer(header: header, data: dataPtr, sampleCount: samples.length),
    );
    _collectDone(handle.value);
    while (_inFlight.length >= _maxInFlight) {
      if (!identical(_handle, handle) || epoch != _writeEpoch) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (!identical(_handle, handle) || epoch != _writeEpoch) {
        return;
      }
      _collectDone(handle.value);
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;
    final handle = _handle;
    if (handle == null) return;
    final result = _WaveOutBindings().waveOutReset(handle.value);
    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutReset failed: $result');
    }
    _collectAll(handle.value);
    _completedSamples = 0;
  }

  @override
  void dispose() {
    _writeEpoch++;
    final handle = _handle;
    _handle = null;
    if (handle == null) {
      return;
    }
    final bindings = _WaveOutBindings();
    bindings.waveOutReset(handle.value);
    _collectAll(handle.value);
    bindings.waveOutClose(handle.value);
    calloc.free(handle);
  }

  @override
  void setVolume(double value) {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final clamped = value.clamp(0.0, 1.0);
    final level = (clamped * 0xFFFF).round();
    final packed = (level & 0xFFFF) | (level << 16);
    _WaveOutBindings().waveOutSetVolume(handle.value, packed);
  }

  @override
  void pause() {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final result = _WaveOutBindings().waveOutPause(handle.value);
    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutPause failed: $result');
    }
  }

  @override
  void resume() {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final result = _WaveOutBindings().waveOutRestart(handle.value);
    if (result != MMSYSERR_NOERROR) {
      throw Exception('waveOutRestart failed: $result');
    }
  }

  void _collectDone(ffi.Pointer<ffi.Void> handle) {
    final bindings = _WaveOutBindings();
    var i = 0;
    while (i < _inFlight.length) {
      final buffer = _inFlight[i];
      if (buffer.header.ref.dwFlags & WHDR_DONE != 0) {
        bindings.waveOutUnprepareHeader(
          handle,
          buffer.header,
          ffi.sizeOf<WAVEHDR>(),
        );
        calloc.free(buffer.header);
        calloc.free(buffer.data);
        _completedSamples += buffer.sampleCount;
        _inFlight.removeAt(i);
        continue;
      }
      i++;
    }
  }

  void _collectAll(ffi.Pointer<ffi.Void> handle) {
    final bindings = _WaveOutBindings();
    for (final buffer in _inFlight) {
      bindings.waveOutUnprepareHeader(
        handle,
        buffer.header,
        ffi.sizeOf<WAVEHDR>(),
      );
      calloc.free(buffer.header);
      calloc.free(buffer.data);
    }
    _inFlight.clear();
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handle;
    if (handle == null) {
      return 0;
    }
    _collectDone(handle.value);
    final out = _completedSamples;
    _completedSamples = 0;
    return out;
  }

  @override
  Future<bool> isIdle() async => _inFlight.isEmpty;
}

class _CoreAudioPlayer implements _NativeAudioPlayer {
  _CoreAudioPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
  }) : _sampleRate = sampleRate,
       _channels = channels,
       _deviceId = deviceId {
    _open();
  }

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  final _CoreAudioBindings _bindings = _CoreAudioBindings();
  ffi.Pointer<ffi.Void> _handle = ffi.nullptr;
  int _writeEpoch = 0;

  void _open() {
    final handle = _bindings.open(_sampleRate, _channels, _deviceId);
    if (handle == ffi.nullptr) {
      throw Exception('CoreAudio open failed.');
    }
    _handle = handle;
  }

  @override
  Future<void> write(Int16List samples) async {
    if (samples.isEmpty) {
      return;
    }
    final epoch = _writeEpoch;
    final dataPtr = calloc<ffi.Int16>(samples.length);
    try {
      dataPtr.asTypedList(samples.length).setAll(0, samples);
      while (true) {
        if (epoch != _writeEpoch) return;
        final handle = _handle;
        if (handle == ffi.nullptr) {
          return;
        }
        final result = _bindings.write(handle, dataPtr, samples.length);
        if (result == 0) {
          break;
        }
        if (result == _coreAudioQueueFull) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          continue;
        }
        throw Exception('CoreAudio write failed: $result');
      }
    } finally {
      calloc.free(dataPtr);
    }
  }

  @override
  Future<void> flush() async {
    _writeEpoch++;
    final handle = _handle;
    if (handle == ffi.nullptr) return;
    final result = _bindings.flush(handle);
    if (result != 0) throw Exception('CoreAudio reset failed: $result');
  }

  @override
  void dispose() {
    _writeEpoch++;
    final handle = _handle;
    _handle = ffi.nullptr;
    if (handle == ffi.nullptr) {
      return;
    }
    _bindings.close(handle);
  }

  @override
  void setVolume(double value) {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return;
    }
    _bindings.setVolume(handle, value);
  }

  @override
  void pause() {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return;
    }
    _bindings.pause(handle);
  }

  @override
  void resume() {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return;
    }
    _bindings.resume(handle);
  }

  @override
  Future<int> collectDoneSamples() async {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return 0;
    }
    return _bindings.collectDoneSamples(handle);
  }

  @override
  Future<bool> isIdle() async {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return true;
    }
    return _bindings.isIdle(handle) != 0;
  }
}

const int _coreAudioQueueFull = -3;

const int WAVE_MAPPER = 0xFFFFFFFF;
const int kDefaultOutputDeviceId = -1;
const int WAVE_FORMAT_PCM = 1;
const int CALLBACK_NULL = 0x00000000;
const int WHDR_DONE = 0x00000001;
const int MMSYSERR_NOERROR = 0;
const int MAXPNAMELEN = 32;

final class WAVEFORMATEX extends ffi.Struct {
  @ffi.Uint16()
  external int wFormatTag;
  @ffi.Uint16()
  external int nChannels;
  @ffi.Uint32()
  external int nSamplesPerSec;
  @ffi.Uint32()
  external int nAvgBytesPerSec;
  @ffi.Uint16()
  external int nBlockAlign;
  @ffi.Uint16()
  external int wBitsPerSample;
  @ffi.Uint16()
  external int cbSize;
}

final class WAVEOUTCAPSW extends ffi.Struct {
  @ffi.Uint16()
  external int wMid;
  @ffi.Uint16()
  external int wPid;
  @ffi.Uint32()
  external int vDriverVersion;
  @ffi.Array<ffi.Uint16>(MAXPNAMELEN)
  external ffi.Array<ffi.Uint16> szPname;
  @ffi.Uint32()
  external int dwFormats;
  @ffi.Uint16()
  external int wChannels;
  @ffi.Uint16()
  external int wReserved1;
  @ffi.Uint32()
  external int dwSupport;
}

String _utf16ArrayToString(ffi.Array<ffi.Uint16> data) {
  final codes = <int>[];
  for (var i = 0; i < MAXPNAMELEN; i++) {
    final value = data[i];
    if (value == 0) {
      break;
    }
    codes.add(value);
  }
  return String.fromCharCodes(codes);
}

final class WAVEHDR extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> lpData;
  @ffi.Uint32()
  external int dwBufferLength;
  @ffi.Uint32()
  external int dwBytesRecorded;
  @ffi.IntPtr()
  external int dwUser;
  @ffi.Uint32()
  external int dwFlags;
  @ffi.Uint32()
  external int dwLoops;
  external ffi.Pointer<WAVEHDR> lpNext;
  @ffi.IntPtr()
  external int reserved;
}

class _WaveBuffer {
  _WaveBuffer({
    required this.header,
    required this.data,
    required this.sampleCount,
  });

  final ffi.Pointer<WAVEHDR> header;
  final ffi.Pointer<ffi.Int16> data;
  final int sampleCount;
}

class _WaveOutBindings {
  _WaveOutBindings()
    : waveOutOpen = _lib
          .lookup<ffi.NativeFunction<_WaveOutOpenNative>>('waveOutOpen')
          .asFunction(),
      waveOutGetNumDevs = _lib
          .lookup<ffi.NativeFunction<_WaveOutGetNumDevsNative>>(
            'waveOutGetNumDevs',
          )
          .asFunction(),
      waveOutGetDevCapsW = _lib
          .lookup<ffi.NativeFunction<_WaveOutGetDevCapsWNative>>(
            'waveOutGetDevCapsW',
          )
          .asFunction(),
      waveOutPrepareHeader = _lib
          .lookup<ffi.NativeFunction<_WaveOutPrepareHeaderNative>>(
            'waveOutPrepareHeader',
          )
          .asFunction(),
      waveOutWrite = _lib
          .lookup<ffi.NativeFunction<_WaveOutWriteNative>>('waveOutWrite')
          .asFunction(),
      waveOutUnprepareHeader = _lib
          .lookup<ffi.NativeFunction<_WaveOutUnprepareHeaderNative>>(
            'waveOutUnprepareHeader',
          )
          .asFunction(),
      waveOutClose = _lib
          .lookup<ffi.NativeFunction<_WaveOutCloseNative>>('waveOutClose')
          .asFunction(),
      waveOutReset = _lib
          .lookup<ffi.NativeFunction<_WaveOutResetNative>>('waveOutReset')
          .asFunction(),
      waveOutSetVolume = _lib
          .lookup<ffi.NativeFunction<_WaveOutSetVolumeNative>>(
            'waveOutSetVolume',
          )
          .asFunction(),
      waveOutPause = _lib
          .lookup<ffi.NativeFunction<_WaveOutPauseNative>>('waveOutPause')
          .asFunction(),
      waveOutRestart = _lib
          .lookup<ffi.NativeFunction<_WaveOutRestartNative>>('waveOutRestart')
          .asFunction();

  static final ffi.DynamicLibrary _lib = ffi.DynamicLibrary.open('winmm.dll');
  final _WaveOutOpenDart waveOutOpen;
  final _WaveOutGetNumDevsDart waveOutGetNumDevs;
  final _WaveOutGetDevCapsWDart waveOutGetDevCapsW;
  final _WaveOutPrepareHeaderDart waveOutPrepareHeader;
  final _WaveOutWriteDart waveOutWrite;
  final _WaveOutUnprepareHeaderDart waveOutUnprepareHeader;
  final _WaveOutCloseDart waveOutClose;
  final _WaveOutResetDart waveOutReset;
  final _WaveOutSetVolumeDart waveOutSetVolume;
  final _WaveOutPauseDart waveOutPause;
  final _WaveOutRestartDart waveOutRestart;
}

typedef _WaveOutOpenNative =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
      ffi.Uint32 uDeviceID,
      ffi.Pointer<WAVEFORMATEX> pwfx,
      ffi.Pointer<ffi.Void> dwCallback,
      ffi.Pointer<ffi.Void> dwInstance,
      ffi.Uint32 fdwOpen,
    );
typedef _WaveOutOpenDart =
    int Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
      int uDeviceID,
      ffi.Pointer<WAVEFORMATEX> pwfx,
      ffi.Pointer<ffi.Void> dwCallback,
      ffi.Pointer<ffi.Void> dwInstance,
      int fdwOpen,
    );

typedef _WaveOutGetNumDevsNative = ffi.Uint32 Function();
typedef _WaveOutGetNumDevsDart = int Function();

typedef _WaveOutGetDevCapsWNative =
    ffi.Uint32 Function(
      ffi.Uint32 uDeviceID,
      ffi.Pointer<WAVEOUTCAPSW> pwoc,
      ffi.Uint32 cbwoc,
    );
typedef _WaveOutGetDevCapsWDart =
    int Function(int uDeviceID, ffi.Pointer<WAVEOUTCAPSW> pwoc, int cbwoc);

typedef _WaveOutPrepareHeaderNative =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Void> hwo,
      ffi.Pointer<WAVEHDR> pwh,
      ffi.Uint32 cbwh,
    );
typedef _WaveOutPrepareHeaderDart =
    int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef _WaveOutWriteNative =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Void> hwo,
      ffi.Pointer<WAVEHDR> pwh,
      ffi.Uint32 cbwh,
    );
typedef _WaveOutWriteDart =
    int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef _WaveOutUnprepareHeaderNative =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Void> hwo,
      ffi.Pointer<WAVEHDR> pwh,
      ffi.Uint32 cbwh,
    );
typedef _WaveOutUnprepareHeaderDart =
    int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef _WaveOutCloseNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);
typedef _WaveOutCloseDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef _WaveOutResetNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);
typedef _WaveOutResetDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef _WaveOutSetVolumeNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo, ffi.Uint32 dwVolume);
typedef _WaveOutSetVolumeDart =
    int Function(ffi.Pointer<ffi.Void> hwo, int dwVolume);

typedef _WaveOutPauseNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);
typedef _WaveOutPauseDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef _WaveOutRestartNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);
typedef _WaveOutRestartDart = int Function(ffi.Pointer<ffi.Void> hwo);

class _CoreAudioBindings {
  _CoreAudioBindings() {
    final lib = ffi.DynamicLibrary.process();
    open = lib
        .lookup<ffi.NativeFunction<_CoreAudioOpenNative>>(
          'phonolite_audio_open',
        )
        .asFunction();
    close = lib
        .lookup<ffi.NativeFunction<_CoreAudioCloseNative>>(
          'phonolite_audio_close',
        )
        .asFunction();
    write = lib
        .lookup<ffi.NativeFunction<_CoreAudioWriteNative>>(
          'phonolite_audio_write',
        )
        .asFunction();
    setVolume = lib
        .lookup<ffi.NativeFunction<_CoreAudioSetVolumeNative>>(
          'phonolite_audio_set_volume',
        )
        .asFunction();
    pause = lib
        .lookup<ffi.NativeFunction<_CoreAudioPauseNative>>(
          'phonolite_audio_pause',
        )
        .asFunction();
    resume = lib
        .lookup<ffi.NativeFunction<_CoreAudioResumeNative>>(
          'phonolite_audio_resume',
        )
        .asFunction();
    flush = lib
        .lookup<ffi.NativeFunction<_CoreAudioIsIdleNative>>(
          'phonolite_audio_flush',
        )
        .asFunction();
    collectDoneSamples = lib
        .lookup<ffi.NativeFunction<_CoreAudioCollectDoneNative>>(
          'phonolite_audio_collect_done_samples',
        )
        .asFunction();
    isIdle = lib
        .lookup<ffi.NativeFunction<_CoreAudioIsIdleNative>>(
          'phonolite_audio_is_idle',
        )
        .asFunction();
    getOutputDeviceCount = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceCountNative>>(
          'phonolite_audio_get_output_device_count',
        )
        .asFunction();
    getOutputDeviceId = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceIdNative>>(
          'phonolite_audio_get_output_device_id',
        )
        .asFunction();
    _getOutputDeviceName = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceNameNative>>(
          'phonolite_audio_get_output_device_name',
        )
        .asFunction();
  }

  static const int _nameBufferLen = 256;
  late final _CoreAudioOpenDart open;
  late final _CoreAudioCloseDart close;
  late final _CoreAudioWriteDart write;
  late final _CoreAudioSetVolumeDart setVolume;
  late final _CoreAudioPauseDart pause;
  late final _CoreAudioResumeDart resume;
  late final _CoreAudioIsIdleDart flush;
  late final _CoreAudioCollectDoneDart collectDoneSamples;
  late final _CoreAudioIsIdleDart isIdle;
  late final _CoreAudioDeviceCountDart getOutputDeviceCount;
  late final _CoreAudioDeviceIdDart getOutputDeviceId;
  late final _CoreAudioDeviceNameDart _getOutputDeviceName;

  String? getOutputDeviceName(int deviceId) {
    final buffer = calloc<ffi.Char>(_nameBufferLen);
    try {
      final result = _getOutputDeviceName(deviceId, buffer, _nameBufferLen);
      if (result != 0) {
        return null;
      }
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }
}

typedef _CoreAudioOpenNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Int32 sampleRate,
      ffi.Int32 channels,
      ffi.Int32 deviceId,
    );
typedef _CoreAudioOpenDart =
    ffi.Pointer<ffi.Void> Function(int sampleRate, int channels, int deviceId);

typedef _CoreAudioCloseNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef _CoreAudioCloseDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef _CoreAudioWriteNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> handle,
      ffi.Pointer<ffi.Int16> samples,
      ffi.Int32 sampleCount,
    );
typedef _CoreAudioWriteDart =
    int Function(
      ffi.Pointer<ffi.Void> handle,
      ffi.Pointer<ffi.Int16> samples,
      int sampleCount,
    );

typedef _CoreAudioSetVolumeNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> handle, ffi.Float volume);
typedef _CoreAudioSetVolumeDart =
    void Function(ffi.Pointer<ffi.Void> handle, double volume);

typedef _CoreAudioPauseNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef _CoreAudioPauseDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef _CoreAudioResumeNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef _CoreAudioResumeDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef _CoreAudioCollectDoneNative =
    ffi.Int64 Function(ffi.Pointer<ffi.Void> handle);
typedef _CoreAudioCollectDoneDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef _CoreAudioIsIdleNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _CoreAudioIsIdleDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef _CoreAudioDeviceCountNative = ffi.Int32 Function();
typedef _CoreAudioDeviceCountDart = int Function();

typedef _CoreAudioDeviceIdNative = ffi.Uint32 Function(ffi.Int32 index);
typedef _CoreAudioDeviceIdDart = int Function(int index);

typedef _CoreAudioDeviceNameNative =
    ffi.Int32 Function(
      ffi.Uint32 deviceId,
      ffi.Pointer<ffi.Char> buffer,
      ffi.Int32 bufferLen,
    );
typedef _CoreAudioDeviceNameDart =
    int Function(int deviceId, ffi.Pointer<ffi.Char> buffer, int bufferLen);

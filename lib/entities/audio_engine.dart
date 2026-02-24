import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show IsolateNameServer;

import 'package:ffi/ffi.dart';
import 'models.dart';
import 'server_connection.dart';
import 'package:phonolite_opus/phonolite_opus.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

const _audioWorkerPortName = 'phonolite_audio_worker';

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

class AudioEngine {
  AudioEngine({
    void Function(String message)? onMessage,
    void Function(
      Duration position,
      Duration bufferedAhead,
      double? bitrateKbps,
      int? rttMs,
    )? onStats,
    void Function(String? sessionId, double? bitrateKbps)? onStreamInfo,
    void Function()? onComplete,
    void Function()? onStarted,
  })  : _onMessage = onMessage,
        _onStats = onStats,
        _onStreamInfo = onStreamInfo,
        _onComplete = onComplete,
        _onStarted = onStarted {
    _shutdownPreviousWorker();
    _spawnWorker();
  }

  final void Function(String message)? _onMessage;
  final void Function(
    Duration position,
    Duration bufferedAhead,
    double? bitrateKbps,
    int? rttMs,
  )? _onStats;
  final void Function(String? sessionId, double? bitrateKbps)? _onStreamInfo;
  final void Function()? _onComplete;
  final void Function()? _onStarted;
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _workerPort;
  final Completer<void> _ready = Completer<void>();
  Isolate? _isolate;
  bool _active = false;
  bool _paused = false;
  int _outputDeviceId = kDefaultOutputDeviceId;

  static void _shutdownPreviousWorker() {
    final existing = IsolateNameServer.lookupPortByName(_audioWorkerPortName);
    if (existing != null) {
      existing.send({'cmd': 'dispose'});
      IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
    }
  }

  Future<void> _spawnWorker() async {
    _isolate = await Isolate.spawn<_AudioWorkerInit>(
      _audioWorkerMain,
      _AudioWorkerInit(_receivePort.sendPort),
    );
    _receivePort.listen(_handleWorkerMessage);
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerPort = message;
      if (!_ready.isCompleted) {
        _ready.complete();
      }
      return;
    }
    if (message is! Map) {
      return;
    }
    final type = message['type'];
    switch (type) {
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
          );
        }
        break;
      case 'stream_info':
        final handler = _onStreamInfo;
        if (handler != null) {
          handler(
            message['session_id']?.toString(),
            (message['bitrate_kbps'] as num?)?.toDouble(),
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
        _active = message['active'] == true;
        _paused = message['paused'] == true;
        break;
      default:
        break;
    }
  }

  Future<void> dispose() async {
    await stop();
    if (_ready.isCompleted) {
      _workerPort?.send({'cmd': 'dispose'});
    }
    _receivePort.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  Future<void> stop() async {
    await _ready.future;
    _active = false;
    _paused = false;
    _sendCmd({'cmd': 'stop'});
  }

  void setVolume(double value) {
    _sendCmd({'cmd': 'volume', 'value': value});
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    _sendCmd({
      'cmd': 'device',
      'device_id': deviceId,
    });
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
        final result = bindings.waveOutGetDevCapsW(i, caps, ffi.sizeOf<WAVEOUTCAPSW>());
        if (result == MMSYSERR_NOERROR) {
          final name = _utf16ArrayToString(caps.ref.szPname);
          devices.add(OutputDevice(id: i, name: name.isEmpty ? 'Device $i' : name));
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
        devices.add(OutputDevice(
          id: deviceId,
          name: name?.isNotEmpty == true ? name! : 'Device $i',
        ));
      }
      return devices;
    }
    return devices;
  }

  void pause() {
    _paused = true;
    _sendCmd({'cmd': 'pause'});
  }

  void resume() {
    _paused = false;
    _sendCmd({'cmd': 'resume'});
  }

  bool get hasActivePlayer => _active;

  bool get isPaused => _paused;

  Future<void> playTrack({
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
  }) async {
    await _ready.future;
    _active = true;
    _paused = false;
    _workerPort?.send({
      'cmd': 'play',
      'track_id': track.id,
      'track_title': track.title,
      'base_url': connection.baseUrl,
      'token': connection.token ?? '',
      'mode': settings.mode,
      'quality': settings.quality,
      'frame_ms': settings.frameMs,
      'start_ms': startOffset.inMilliseconds,
      'queue': queueTrackIds,
      'device_id': _outputDeviceId,
      'quic_port': quicPort,
    });
  }

  void _sendCmd(Map<String, dynamic> message) {
    if (!_ready.isCompleted) {
      _ready.future.then((_) => _workerPort?.send(message));
      return;
    }
    _workerPort?.send(message);
  }

  Future<bool> seekTo(Duration position) async {
    await _ready.future;
    if (!_active) {
      return false;
    }
    _workerPort?.send({
      'cmd': 'seek',
      'position_ms': position.inMilliseconds,
    });
    return true;
  }
}

class _AudioWorkerEngine {
  _AudioWorkerEngine({
    required void Function(Map<String, dynamic> message) send,
  }) : _send = send;

  final void Function(Map<String, dynamic> message) _send;
  int _playbackId = 0;
  _PlaybackSession? _session;
  double _volume = 1.0;
  int _outputDeviceId = kDefaultOutputDeviceId;

  void dispose() {
    stop();
  }

  void stop() {
    _playbackId++;
    _session?.requestStop();
    _session = null;
    _send({'type': 'state', 'active': false, 'paused': false});
  }

  void pause() {
    _session?.pause();
  }

  void resume() {
    _session?.resume();
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _session?.setVolume(_volume);
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    _session?.setOutputDevice(deviceId);
  }

  Future<void> seekTo(Duration position) async {
    final session = _session;
    if (session == null) {
      return;
    }
    await session.seekTo(position);
  }

  Future<void> playTrack({
    required String trackId,
    required String trackTitle,
    required String baseUrl,
    required String token,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
  }) async {
    stop();
    final playbackId = ++_playbackId;
    final session = _PlaybackSession(
      send: _send,
      playbackId: playbackId,
      getPlaybackId: () => _playbackId,
      trackId: trackId,
      trackTitle: trackTitle,
      baseUrl: baseUrl,
      token: token,
      quicPort: quicPort,
      settings: settings,
      startOffset: startOffset,
      queueTrackIds: queueTrackIds,
      volume: _volume,
      outputDeviceId: _outputDeviceId,
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
  _PlaybackSession({
    required void Function(Map<String, dynamic> message) send,
    required int playbackId,
    required int Function() getPlaybackId,
    required this.trackId,
    required this.trackTitle,
    required this.baseUrl,
    required this.token,
    required this.quicPort,
    required this.settings,
    required this.startOffset,
    required this.queueTrackIds,
    required double volume,
    required int outputDeviceId,
  })  : _send = send,
        _playbackId = playbackId,
        _getPlaybackId = getPlaybackId,
        _volume = volume,
        _outputDeviceId = outputDeviceId;

  final void Function(Map<String, dynamic> message) _send;
  final int _playbackId;
  final int Function() _getPlaybackId;
  final String trackId;
  final String trackTitle;
  final String baseUrl;
  final String token;
  final int? quicPort;
  final StreamSettings settings;
  final Duration startOffset;
  final List<String> queueTrackIds;
  double _volume;
  int _outputDeviceId;
  int _baseOffsetMs = 0;
  int _pendingClientSkipMs = 0;
  int? _pendingSeekMs;
  bool _discardUntilSeekMarker = false;
  bool _pumpRunning = false;
  bool _pumpSuspended = false;
  bool _pumpWriting = false;
  bool _quickStart = false;

  bool _stopRequested = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _autoPaused = false;
  bool _reportedStart = false;
  bool _startedPlayback = false;
  bool _streamEnded = false;

  int _sampleRate = 48000;
  int _channels = 2;
  int _frameSamples = 0;
  int _preSkipSamples = 0;
  int _skipSamples = 0;

  double _prebufferSeconds = Platform.isIOS ? 6.0 : 10.0;
  double _rebufferMinSeconds = 1.0;
  double _rebufferTargetSeconds = 8.0;
  static const double _prebufferSecondsLocal = 2.0;
  static const double _rebufferMinSecondsLocal = 0.4;
  static const double _rebufferTargetSecondsLocal = 2.0;
  static const double _seekStartSeconds = 0.05;
  static const double _seekCatchupMinSeconds = 0.2;
  static const double _seekCatchupTargetSeconds = 0.4;
  static const int _pumpChunkMs = 200;
  static const bool _serverBackpressureEnabled = true;

  int _prebufferTargetSamples = 0;
  int _rebufferMinSamples = 0;
  int _rebufferTargetSamples = 0;
  int _pumpChunkSamples = 0;

  QuicClient? _quic;
  OpusDecoder? _decoder;
  _NativeAudioPlayer? _player;
  _PcmRingBuffer? _buffer;
  Timer? _statsTimer;
  static const int _playbackReportIntervalMs = 1000;
  int _lastPlaybackReportAt = 0;

  int _queuedToPlayerSamples = 0;
  int _playedSamples = 0;
  int _bytesReceived = 0;
  int _lastBitrateBytes = 0;
  DateTime? _lastBitrateAt;

  bool get _isActive => !_stopRequested && _playbackId == _getPlaybackId();

  void requestStop() {
    _stopRequested = true;
    _stopStats();
    _quic?.close();
  }

  void pause() {
    _userPaused = true;
    if (_paused) {
      return;
    }
    _paused = true;
    final player = _player;
    if (player != null) {
      player.pause();
      _send({'type': 'state', 'active': true, 'paused': true});
    }
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    _userPaused = false;
    _autoPaused = false;
    final player = _player;
    if (player != null) {
      player.resume();
      _send({'type': 'state', 'active': true, 'paused': false});
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
  }

  Future<void> seekTo(Duration position) async {
    final quic = _quic;
    if (quic == null) {
      _log('Seek ignored: QUIC client not ready.');
      return;
    }
    _quickStart = true;
    final ms = position.inMilliseconds;
    final previousBaseOffset = _baseOffsetMs;
    _pendingSeekMs = ms;
    _streamEnded = false;
    _discardUntilSeekMarker = true;
    _baseOffsetMs = ms;
    _log('Sending QUIC seek to ${ms}ms');
    try {
      quic.seek(trackId: trackId, positionMs: ms);
    } catch (err) {
      _pendingSeekMs = null;
      _discardUntilSeekMarker = false;
      _baseOffsetMs = previousBaseOffset;
      _log('QUIC seek failed: $err');
      return;
    }
    await _flushForSeek();
  }

  void _configureBufferProfile(String host) {
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (isLoopback) {
      _prebufferSeconds = _prebufferSecondsLocal;
      _rebufferMinSeconds = _rebufferMinSecondsLocal;
      _rebufferTargetSeconds = _rebufferTargetSecondsLocal;
    } else {
      _prebufferSeconds = Platform.isIOS ? 6.0 : 10.0;
      _rebufferMinSeconds = 1.0;
      _rebufferTargetSeconds = 8.0;
    }
    _log(
      'Buffer profile: prebuffer=${_prebufferSeconds.toStringAsFixed(1)}s '
      'rebuffer_min=${_rebufferMinSeconds.toStringAsFixed(1)}s '
      'rebuffer_target=${_rebufferTargetSeconds.toStringAsFixed(1)}s',
    );
  }

  Future<void> run() async {
    try {
      await _runPlayback();
    } catch (err) {
      _log('Playback failed: $err');
      _send({'type': 'state', 'active': false, 'paused': false});
    } finally {
      _stopStats();
      _decoder?.dispose();
      _decoder = null;
      _player?.dispose();
      _player = null;
      _quic?.close();
      _quic = null;
    }
  }

  bool _openTrackSafe(
    QuicClient quic, {
    required String trackId,
    required StreamSettings settings,
    required List<String> queueTrackIds,
  }) {
    try {
      quic.openTrack(
        trackId: trackId,
        mode: settings.mode,
        quality: settings.quality,
        frameMs: settings.frameMs,
        queue: queueTrackIds,
      );
      return true;
    } catch (err) {
      _log('QUIC open failed: $err');
      return false;
    }
  }

  Future<void> _runPlayback() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isIOS)) {
      throw Exception(
        'Audio playback is only implemented for Windows and Apple platforms right now.',
      );
    }

    _queuedToPlayerSamples = 0;
    _playedSamples = 0;
    _bytesReceived = 0;
    _lastBitrateBytes = 0;
    _lastBitrateAt = null;
    _reportedStart = false;
    _startedPlayback = false;
    _streamEnded = false;
    _baseOffsetMs = startOffset.inMilliseconds;
    _pendingClientSkipMs = startOffset.inMilliseconds;
    _quickStart = startOffset.inMilliseconds > 0;
    _pendingSeekMs = null;
    _pumpRunning = false;

    final uri = Uri.parse(baseUrl);
    var host = uri.host.isNotEmpty ? uri.host : '127.0.0.1';
    _configureBufferProfile(host);
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      host = '127.0.0.1';
    }

    final httpPort =
        uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final resolvedQuicPort =
        (quicPort != null && quicPort! > 0) ? quicPort! : httpPort + 1;
    _log(
      'QUIC config: base_url=$baseUrl host=$host http_port=$httpPort '
      'quic_port=$resolvedQuicPort token_len=${token.length} platform=${Platform.operatingSystem}',
    );
    if (Platform.isIOS &&
        (host == '127.0.0.1' || host == 'localhost' || host == '::1')) {
      _log(
        'Warning: QUIC host is loopback on iOS. Use a LAN IP/hostname to reach the server.',
      );
    }
    _log('Opening QUIC stream: $host:$resolvedQuicPort');
    var quic =
        QuicClient.connect(host: host, port: resolvedQuicPort, token: token);
    _quic = quic;
    if (!_openTrackSafe(
      quic,
      trackId: trackId,
      settings: settings,
      queueTrackIds: queueTrackIds,
    )) {
      _log('QUIC open failed; reconnecting.');
      quic.close();
      quic = QuicClient.connect(host: host, port: resolvedQuicPort, token: token);
      _quic = quic;
      if (!_openTrackSafe(
        quic,
        trackId: trackId,
        settings: settings,
        queueTrackIds: queueTrackIds,
      )) {
        _log('QUIC open failed after retry; aborting playback.');
        _send({'type': 'state', 'active': false, 'paused': false});
        return;
      }
    }

    final reader = _ByteQueue();
    RawOpusHeader? header;
    OpusDecoder? decoder;
    int? maxFrameSize;
    int? pendingFrameLen;
    int? headerLen;
    var headerBuilder = BytesBuilder();
    var bytesReceived = 0;
    var framesDecoded = 0;
    var lastLogTime = DateTime.now();
    const logInterval = Duration(seconds: 2);
    var lastFrameLen = 0;
    var decodeErrors = 0;
    var debugFramesLogged = 0;
    final playbackStartedAt = DateTime.now();
    var noBytesWarned = false;
    Future<void>? pumpTask;

    Future<void> resetForSeek() async {
      _pumpSuspended = true;
      await _waitForPumpIdle();
      _streamEnded = false;
      _startedPlayback = false;
      _reportedStart = false;
      _autoPaused = false;
      _discardUntilSeekMarker = false;
      _queuedToPlayerSamples = 0;
      _playedSamples = 0;
      _bytesReceived = 0;
      _lastBitrateBytes = 0;
      _lastBitrateAt = null;
      bytesReceived = 0;
      framesDecoded = 0;
      lastFrameLen = 0;
      decodeErrors = 0;
      debugFramesLogged = 0;
      header = null;
      headerLen = null;
      headerBuilder = BytesBuilder();
      pendingFrameLen = null;
      decoder?.dispose();
      decoder = null;
      _decoder = null;
      _player?.dispose();
      _player = null;
      _buffer = null;
      maxFrameSize = null;
      _preSkipSamples = 0;
      _skipSamples = 0;
      _frameSamples = 0;
      _pendingClientSkipMs = 0;
      if (_pendingSeekMs != null) {
        _baseOffsetMs = _pendingSeekMs!;
      }
      _pendingSeekMs = null;
      _pumpSuspended = false;
    }

    final readBuffer = Uint8List(64 * 1024);

    while (_isActive) {
      final buffer = _buffer;
      if (buffer != null && !_streamEnded) {
        final minFree = _pumpChunkSamples > 0 ? _pumpChunkSamples : 1;
        if (buffer.free < minFree) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          continue;
        }
      }
      final read = quic.read(readBuffer);
      if (read < 0 && read != -5) {
        final detail = quic.lastError();
        throw Exception(
          'QUIC read failed: $read${detail == null ? '' : ' ($detail)'}',
        );
      }
      if (read == 0) {
        final detail = quic.lastError();
        _log('QUIC stream closed: ${detail ?? 'no detail'}');
        _streamEnded = true;
      } else if (read > 0) {
        final data = Uint8List.fromList(readBuffer.sublist(0, read));
        bytesReceived += data.length;
        _bytesReceived = bytesReceived;
        reader.add(data);
      }

      while (_isActive) {
        if (_discardUntilSeekMarker) {
          _resyncRawHeader(reader);
          final prefix = reader.peek(12);
          if (prefix != null && _hasRawHeaderMagic(prefix)) {
            _log('Seek marker missing; resyncing on raw header.');
            await resetForSeek();
            continue;
          }
        }
        if (header == null) {
          if (headerLen == null) {
            final prefix = reader.peek(12);
            if (prefix == null) {
              break;
            }
            if (!_hasRawHeaderMagic(prefix)) {
              _resyncRawHeader(reader);
              continue;
            }
            if (prefix[8] != 1) {
              reader.discard(1);
              continue;
            }
            final length = prefix[10] | (prefix[11] << 8);
            if (length < _rawHeaderMinLen) {
              reader.discard(1);
              continue;
            }
            headerLen = length;
            headerBuilder = BytesBuilder();
            final consumed = reader.read(12);
            if (consumed == null) {
              headerLen = null;
              break;
            }
            headerBuilder.add(consumed);
            _log('Raw header length: $headerLen');
          }
          final remaining = headerLen! - headerBuilder.length;
          if (remaining > 0) {
            final rest = reader.read(remaining);
            if (rest == null) {
              break;
            }
            headerBuilder.add(rest);
          }
          final headerBytes = headerBuilder.takeBytes();
          _log('Raw header bytes read: ${headerBytes.length}');
          try {
            header = RawOpusHeader.parse(headerBytes);
          } catch (err) {
            _log('Raw header parse failed; resyncing. ($err)');
            header = null;
            headerLen = null;
            headerBuilder = BytesBuilder();
            continue;
          }
          final headerTrackId = _extractHeaderTrackId(headerBytes);
          if (headerTrackId != null && headerTrackId != trackId) {
            _log(
              'Raw header track mismatch; resyncing (got $headerTrackId expected $trackId).',
            );
            header = null;
            headerLen = null;
            headerBuilder = BytesBuilder();
            continue;
          }
          final parsedHeader = header;
          if (parsedHeader == null) {
            headerLen = null;
            headerBuilder = BytesBuilder();
            continue;
          }
          _log(
            'Opus header: ${parsedHeader.sampleRate} Hz, ${parsedHeader.channels}ch, frame ${parsedHeader.frameMs}ms',
          );
          _log('Opus duration: ${parsedHeader.durationMs} ms');
          _frameSamples =
              (parsedHeader.sampleRate * parsedHeader.frameMs / 1000).round();
          _log('Opus frame samples per channel: $_frameSamples');
          final createdDecoder = OpusDecoder(
            sampleRate: parsedHeader.sampleRate,
            channels: parsedHeader.channels,
          );
          decoder = createdDecoder;
          _decoder = createdDecoder;
          maxFrameSize = createdDecoder.maxFrameSize;
          _log('Opus max frame size: $maxFrameSize');
          _sampleRate = parsedHeader.sampleRate;
          _channels = parsedHeader.channels;
          _preSkipSamples = parsedHeader.preSkip * parsedHeader.channels;
          final skipMs = _pendingClientSkipMs;
          _pendingClientSkipMs = 0;
          _skipSamples =
              (skipMs * parsedHeader.sampleRate ~/ 1000) * parsedHeader.channels;

          _pumpChunkSamples =
              ((_sampleRate * _channels * _pumpChunkMs) / 1000).round();
          if (_pumpChunkSamples <= 0) {
            _pumpChunkSamples = _frameSamples * _channels;
          }
          if (_quickStart) {
            var startSamples = _frameSamples * _channels;
            if (startSamples <= 0) {
              startSamples =
                  (_sampleRate * _channels * _seekStartSeconds).round();
            }
            if (startSamples <= 0) {
              startSamples = 1;
            }
            _prebufferTargetSamples = startSamples;
            _rebufferMinSamples =
                (_sampleRate * _channels * _seekCatchupMinSeconds).round();
            _rebufferTargetSamples =
                (_sampleRate * _channels * _seekCatchupTargetSeconds).round();
          } else {
            _prebufferTargetSamples =
                (_sampleRate * _channels * _prebufferSeconds).round();
            _rebufferMinSamples =
                (_sampleRate * _channels * _rebufferMinSeconds).round();
            _rebufferTargetSamples =
                (_sampleRate * _channels * _rebufferTargetSeconds).round();
          }

          final targetSeconds = _quickStart
              ? _seekCatchupTargetSeconds
              : (_prebufferSeconds > _rebufferTargetSeconds
                  ? _prebufferSeconds
                  : _rebufferTargetSeconds);
          final capacitySeconds = targetSeconds * 4.0;
          final capacitySamples =
              (capacitySeconds * _sampleRate * _channels).round();
          final minCapacitySamples = _rebufferTargetSamples * 2;
          var finalCapacity = capacitySamples;
          if (minCapacitySamples > finalCapacity) {
            finalCapacity = minCapacitySamples;
          }
          final minPumpCapacity = _pumpChunkSamples * 4;
          if (minPumpCapacity > finalCapacity) {
            finalCapacity = minPumpCapacity;
          }
          _buffer = _PcmRingBuffer(finalCapacity);

          _player = _createPlayer(
            sampleRate: parsedHeader.sampleRate,
            channels: parsedHeader.channels,
            deviceId: _outputDeviceId,
          );
          _player?.setVolume(_volume);
          if (_paused) {
            _player?.pause();
          }
          _send({'type': 'state', 'active': true, 'paused': _paused});
          _startStats();
          if (!_pumpRunning) {
            pumpTask = _runPump();
          }
          continue;
        }
        if (pendingFrameLen == null) {
          final lenBytes = reader.read(2);
          if (lenBytes == null) {
            break;
          }
          pendingFrameLen = lenBytes[0] | (lenBytes[1] << 8);
          if (pendingFrameLen == _rawSeekMarker) {
            _log('Seek marker received; resetting decoder.');
            pendingFrameLen = null;
            await resetForSeek();
            continue;
          }
          if (pendingFrameLen == 0) {
            if (_discardUntilSeekMarker) {
              // Ignore EOS from the old position while waiting for the seek marker.
              pendingFrameLen = null;
              continue;
            }
            _streamEnded = true;
            break;
          }
        }

        if (_discardUntilSeekMarker) {
          if (pendingFrameLen == 0) {
            pendingFrameLen = null;
            continue;
          }
          final discard = reader.read(pendingFrameLen!);
          if (discard == null) {
            break;
          }
          pendingFrameLen = null;
          continue;
        }

        final packet = reader.read(pendingFrameLen!);
        if (packet == null) {
          break;
        }
        pendingFrameLen = null;

        final activeHeader = header;
        if (activeHeader == null) {
          _log('Opus header missing during decode.');
          return;
        }
        final frameHint =
            (activeHeader.sampleRate * activeHeader.frameMs / 1000).round();
        final frameSize = maxFrameSize == null
            ? frameHint
            : frameHint.clamp(1, maxFrameSize!);
        lastFrameLen = packet.length;

        Int16List samples;
        try {
          final activeDecoder = decoder;
          if (activeDecoder == null) {
            _log('Opus decoder missing during decode.');
            return;
          }
          samples = activeDecoder.decode(packet, frameSize: frameSize);
        } catch (err) {
          decodeErrors++;
          _log('Decode error (${decodeErrors}): $err');
          continue;
        }

        if (samples.isEmpty) {
          continue;
        }
        framesDecoded++;

        if (debugFramesLogged < 5) {
          debugFramesLogged++;
          final sampleCount = samples.length;
          var min = samples.first;
          var max = samples.first;
          var sum = 0;
          for (final v in samples) {
            if (v < min) min = v;
            if (v > max) max = v;
            sum += v;
          }
          final avg = sum / sampleCount;
          _log(
            'Frame ${framesDecoded}: packet=${packet.length} bytes, samples=$sampleCount, '
            'min=$min max=$max avg=${avg.toStringAsFixed(1)}',
          );
          if (sampleCount % activeHeader.channels != 0) {
            _log(
              'Warning: samples not multiple of channels (${activeHeader.channels}).',
            );
          }
          final expected = frameHint * activeHeader.channels;
          if (sampleCount != expected) {
            _log('Warning: samples != expected (${expected}).');
          }
        }

        if (_preSkipSamples > 0) {
          if (samples.length <= _preSkipSamples) {
            _preSkipSamples -= samples.length;
            continue;
          }
          samples = samples.sublist(_preSkipSamples);
          _preSkipSamples = 0;
        }

        if (_skipSamples > 0) {
          if (samples.length <= _skipSamples) {
            _skipSamples -= samples.length;
            continue;
          }
          samples = samples.sublist(_skipSamples);
          _skipSamples = 0;
        }

        if (samples.isEmpty) {
          continue;
        }

        await _writeToBuffer(samples);
      }

      if (!noBytesWarned &&
          bytesReceived == 0 &&
          DateTime.now().difference(playbackStartedAt) >
              const Duration(seconds: 3)) {
        final detail = quic.lastError();
        _log(
          'QUIC waiting for data (0 bytes received). '
          'last_error=${detail ?? 'none'}',
        );
        noBytesWarned = true;
      }

      if (_streamEnded) {
        break;
      }
      if (read == -5) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final now = DateTime.now();
      if (now.difference(lastLogTime) >= logInterval) {
        lastLogTime = now;
        _log(
          'Stream stats: bytes=${bytesReceived}, frames=${framesDecoded}, '
          'buffered=${reader.available} bytes, last_frame=${lastFrameLen}, '
          'decode_errors=${decodeErrors}',
        );
      }
    }

    _streamEnded = true;
    _log('Stream ended.');
    if (_autoPaused && !_userPaused) {
      _resumeFromAutoPause();
    }
    if (pumpTask != null) {
      await pumpTask;
    }
    if (_isActive) {
      _send({'type': 'complete'});
    }
  }

  Future<void> _runPump() async {
    _pumpRunning = true;
    try {
      while (_isActive) {
        final player = _player;
        final buffer = _buffer;
        if (player == null || buffer == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        if (_pumpSuspended) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }

        if (!_startedPlayback) {
          if (buffer.length == 0 && _streamEnded) {
            return;
          }
          if (!_streamEnded && buffer.length < _prebufferTargetSamples) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          _startedPlayback = true;
          _reportStarted();
        }

        if (_paused) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
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

        _pumpWriting = true;
        try {
          await _writeSamples(player, chunk);
        } catch (err) {
          _pumpWriting = false;
          _log('Audio write error: $err');
          if (_pumpSuspended || !_isActive) {
            return;
          }
          rethrow;
        } finally {
          _pumpWriting = false;
        }
      }
    } finally {
      _pumpRunning = false;
    }
  }

  Future<void> _waitForPumpIdle() async {
    if (!_pumpRunning) {
      return;
    }
    for (var i = 0; i < 80; i++) {
      if (!_pumpWriting) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> _flushForSeek() async {
    _pumpSuspended = true;
    await _waitForPumpIdle();
    _queuedToPlayerSamples = 0;
    _playedSamples = 0;
    _buffer = null;
    final player = _player;
    _player = null;
    player?.dispose();
    _pumpSuspended = false;
  }

  Future<void> _writeToBuffer(Int16List samples) async {
    final buffer = _buffer;
    if (buffer == null) {
      return;
    }
    var offset = 0;
    while (offset < samples.length && _isActive) {
      final written = buffer.write(samples, offset);
      if (written == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      offset += written;
    }
  }

  Future<void> _writeSamples(_NativeAudioPlayer player, Int16List samples) async {
    await player.write(samples);
    _queuedToPlayerSamples += samples.length;
  }

  Future<void> _drainPlayer(_NativeAudioPlayer player) async {
    while (_isActive && !player.isIdle) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _playedSamples += player.collectDoneSamples();
    }
  }

  void _reportStarted() {
    if (_reportedStart) {
      return;
    }
    _reportedStart = true;
    _quickStart = false;
    _log('Audio playback started.');
    _send({'type': 'started'});
  }

  void _startStats() {
    _stopStats();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final player = _player;
      if (player != null) {
        _playedSamples += player.collectDoneSamples();
      }
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
      final bufferOnlyMs = samplesPerSecond == 0
          ? 0
          : (bufferSamples * 1000 ~/ samplesPerSecond);

      final quic = _quic;
      if (quic != null && _serverBackpressureEnabled) {
        final targetMs = (_rebufferTargetSeconds * 1000).round();
        try {
          quic.sendBufferStats(
            bufferMs: bufferOnlyMs,
            targetMs: targetMs,
          );
        } catch (_) {
          // Ignore closed/failed QUIC stats updates.
        }
      }

      if (quic != null) {
        try {
          final stats = quic.pollStats();
          if (stats != null) {
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

      final playedMs = samplesPerSecond == 0
          ? 0
          : (_playedSamples * 1000 ~/ samplesPerSecond);
      final position = Duration(milliseconds: _baseOffsetMs + playedMs);
      _maybeRebuffer(bufferedSamples);
      _maybeReportPlayback(quic, position);
      _send({
        'type': 'stats',
        'position_ms': position.inMilliseconds,
        'buffered_ms': bufferedMs,
        'bitrate_kbps': _currentBitrateKbps(),
        'rtt_ms': rttMs,
      });
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  void _maybeReportPlayback(QuicClient? quic, Duration position) {
    if (quic == null || !_reportedStart) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPlaybackReportAt < _playbackReportIntervalMs) {
      return;
    }
    _lastPlaybackReportAt = nowMs;
    final playing = !_paused && !_autoPaused && !_streamEnded;
    try {
      quic.sendPlayback(
        trackId: trackId,
        positionMs: position.inMilliseconds,
        playing: playing,
      );
    } catch (_) {
      // Ignore playback stat errors from closed/failed QUIC sessions.
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
    if (_userPaused) {
      return;
    }
    if (!_autoPaused && bufferedSamples <= _rebufferMinSamples) {
      _pauseForBuffer();
      return;
    }
    if (_autoPaused && bufferedSamples >= _rebufferTargetSamples) {
      _resumeFromAutoPause();
    }
  }

  void _pauseForBuffer() {
    final player = _player;
    if (player == null) {
      return;
    }
    player.pause();
    _paused = true;
    _autoPaused = true;
    _send({'type': 'state', 'active': true, 'paused': true});
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
    _send({'type': 'state', 'active': true, 'paused': false});
  }

  void _log(String message) {
    _send({'type': 'message', 'text': message});
  }
}

class _PcmRingBuffer {
  _PcmRingBuffer(int capacitySamples)
      : _buffer = Int16List(capacitySamples),
        _capacity = capacitySamples;

  final Int16List _buffer;
  final int _capacity;
  int _readIndex = 0;
  int _writeIndex = 0;
  int _length = 0;

  int get length => _length;

  int get capacity => _capacity;

  int get free => _capacity - _length;

  int write(Int16List data, int offset) {
    if (offset >= data.length || _length >= _capacity) {
      return 0;
    }
    final available = _capacity - _length;
    final remaining = data.length - offset;
    final toWrite = remaining < available ? remaining : available;

    final firstPart = toWrite < (_capacity - _writeIndex)
        ? toWrite
        : (_capacity - _writeIndex);
    _buffer.setRange(_writeIndex, _writeIndex + firstPart, data, offset);
    final leftover = toWrite - firstPart;
    if (leftover > 0) {
      _buffer.setRange(0, leftover, data, offset + firstPart);
    }
    _writeIndex = (_writeIndex + toWrite) % _capacity;
    _length += toWrite;
    return toWrite;
  }

  Int16List? read(int count) {
    if (_length == 0 || count <= 0) {
      return null;
    }
    final toRead = count < _length ? count : _length;
    final out = Int16List(toRead);
    final firstPart = toRead < (_capacity - _readIndex)
        ? toRead
        : (_capacity - _readIndex);
    out.setRange(0, firstPart, _buffer, _readIndex);
    final leftover = toRead - firstPart;
    if (leftover > 0) {
      out.setRange(firstPart, toRead, _buffer, 0);
    }
    _readIndex = (_readIndex + toRead) % _capacity;
    _length -= toRead;
    return out;
  }
}

const List<int> _rawHeaderMagic = [79, 80, 85, 83, 82, 48, 49, 0];
const int _rawHeaderMinLen = 40;
const int _rawSeekMarker = 0xFFFF;

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

void _resyncRawHeader(_ByteQueue reader) {
  final idx = reader.indexOf(_rawHeaderMagic);
  if (idx == 0) {
    return;
  }
  if (idx > 0) {
    reader.discard(idx);
    return;
  }
  final keep = _rawHeaderMagic.length - 1;
  final discard = reader.available - keep;
  if (discard > 0) {
    reader.discard(discard);
  }
}

class _AudioWorkerInit {
  _AudioWorkerInit(this.sendPort);

  final SendPort sendPort;
}

void _audioWorkerMain(_AudioWorkerInit init) {
  final receivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping(_audioWorkerPortName);
  IsolateNameServer.registerPortWithName(
    receivePort.sendPort,
    _audioWorkerPortName,
  );
  init.sendPort.send(receivePort.sendPort);
  final engine = _AudioWorkerEngine(send: (message) {
    init.sendPort.send(message);
  });

  receivePort.listen((message) async {
    if (message is! Map) {
      return;
    }
    final cmd = message['cmd'];
    switch (cmd) {
      case 'play':
        final rawQueue = message['queue'];
        final queue = rawQueue is List
            ? rawQueue.map((item) => item.toString()).toList()
            : const <String>[];
        await engine.playTrack(
          trackId: message['track_id']?.toString() ?? '',
          trackTitle: message['track_title']?.toString() ?? '',
          baseUrl: message['base_url']?.toString() ?? '',
          token: message['token']?.toString() ?? '',
          quicPort: (message['quic_port'] as num?)?.toInt(),
          settings: StreamSettings(
            mode: message['mode']?.toString() ?? 'auto',
            quality: message['quality']?.toString() ?? 'high',
            frameMs: (message['frame_ms'] as num?)?.toInt() ?? 60,
          ),
          startOffset: Duration(milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0),
          queueTrackIds: queue,
        );
        break;
      case 'stop':
        engine.stop();
        break;
      case 'pause':
        engine.pause();
        break;
      case 'resume':
        engine.resume();
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
        await engine.seekTo(Duration(milliseconds: ms));
        break;
      case 'dispose':
        engine.dispose();
        receivePort.close();
        Isolate.exit();
        break;
      default:
        break;
    }
  });
}

class _ByteQueue {
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  int get available => _buffer.length - _offset;

  Uint8List? peek(int length) {
    if (available < length) {
      return null;
    }
    return _buffer.sublist(_offset, _offset + length);
  }

  void discard(int length) {
    if (length <= 0) {
      return;
    }
    if (length >= available) {
      _buffer = Uint8List(0);
      _offset = 0;
      return;
    }
    _offset += length;
    if (_offset == _buffer.length) {
      _buffer = Uint8List(0);
      _offset = 0;
    }
  }

  int indexOf(List<int> pattern) {
    if (pattern.isEmpty) {
      return 0;
    }
    final maxStart = _buffer.length - pattern.length;
    for (var i = _offset; i <= maxStart; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (_buffer[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return i - _offset;
      }
    }
    return -1;
  }

  void add(Uint8List data) {
    if (_offset == _buffer.length) {
      _buffer = data;
      _offset = 0;
      return;
    }
    final builder = BytesBuilder();
    builder.add(_buffer.sublist(_offset));
    builder.add(data);
    _buffer = builder.takeBytes();
    _offset = 0;
  }

  Uint8List? read(int length) {
    if (available < length) {
      return null;
    }
    final out = Uint8List.fromList(
      _buffer.sublist(_offset, _offset + length),
    );
    _offset += length;
    if (_offset == _buffer.length) {
      _buffer = Uint8List(0);
      _offset = 0;
    }
    return out;
  }
}

abstract class _NativeAudioPlayer {
  Future<void> write(Int16List samples);
  void dispose();
  void setVolume(double value);
  void pause();
  void resume();
  int collectDoneSamples();
  bool get isIdle;
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
  throw Exception('Audio playback is only implemented for Windows and macOS right now.');
}

class _WaveOutPlayer implements _NativeAudioPlayer {
  _WaveOutPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
  })  : _sampleRate = sampleRate,
        _channels = channels,
        _deviceId = deviceId {
    _open();
  }

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  ffi.Pointer<ffi.Pointer<ffi.Void>>? _handle;
  final List<_WaveBuffer> _inFlight = [];
  static const int _maxInFlight = 24;
  int _completedSamples = 0;

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

    final deviceId = _deviceId == kDefaultOutputDeviceId ? WAVE_MAPPER : _deviceId;
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

    result = bindings.waveOutWrite(
      handle.value,
      header,
      ffi.sizeOf<WAVEHDR>(),
    );
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

    _inFlight.add(_WaveBuffer(header: header, data: dataPtr, sampleCount: samples.length));
    _collectDone(handle.value);
    while (_inFlight.length > _maxInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      _collectDone(handle.value);
    }
  }

  @override
  void dispose() {
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
    _WaveOutBindings().waveOutPause(handle.value);
  }

  @override
  void resume() {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    _WaveOutBindings().waveOutRestart(handle.value);
  }

  void _collectDone(ffi.Pointer<ffi.Void> handle) {
    final bindings = _WaveOutBindings();
    var i = 0;
    while (i < _inFlight.length) {
      final buffer = _inFlight[i];
      if (buffer.header.ref.dwFlags & WHDR_DONE != 0) {
        bindings.waveOutUnprepareHeader(handle, buffer.header, ffi.sizeOf<WAVEHDR>());
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
      bindings.waveOutUnprepareHeader(handle, buffer.header, ffi.sizeOf<WAVEHDR>());
      calloc.free(buffer.header);
      calloc.free(buffer.data);
    }
    _inFlight.clear();
  }

  @override
  int collectDoneSamples() {
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
  bool get isIdle => _inFlight.isEmpty;
}

class _CoreAudioPlayer implements _NativeAudioPlayer {
  _CoreAudioPlayer({
    required int sampleRate,
    required int channels,
    required int deviceId,
  })  : _sampleRate = sampleRate,
        _channels = channels,
        _deviceId = deviceId {
    _open();
  }

  final int _sampleRate;
  final int _channels;
  final int _deviceId;
  final _CoreAudioBindings _bindings = _CoreAudioBindings();
  ffi.Pointer<ffi.Void> _handle = ffi.nullptr;

  void _open() {
    final handle = _bindings.open(_sampleRate, _channels, _deviceId);
    if (handle == ffi.nullptr) {
      throw Exception('CoreAudio open failed.');
    }
    _handle = handle;
  }

  @override
  Future<void> write(Int16List samples) async {
    final handle = _handle;
    if (handle == ffi.nullptr || samples.isEmpty) {
      return;
    }
    final dataPtr = calloc<ffi.Int16>(samples.length);
    try {
      dataPtr.asTypedList(samples.length).setAll(0, samples);
      while (true) {
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
  void dispose() {
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
  int collectDoneSamples() {
    final handle = _handle;
    if (handle == ffi.nullptr) {
      return 0;
    }
    return _bindings.collectDoneSamples(handle);
  }

  @override
  bool get isIdle {
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
  _WaveBuffer({required this.header, required this.data, required this.sampleCount});

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
            .lookup<ffi.NativeFunction<_WaveOutGetNumDevsNative>>('waveOutGetNumDevs')
            .asFunction(),
        waveOutGetDevCapsW = _lib
            .lookup<ffi.NativeFunction<_WaveOutGetDevCapsWNative>>('waveOutGetDevCapsW')
            .asFunction(),
        waveOutPrepareHeader = _lib
            .lookup<ffi.NativeFunction<_WaveOutPrepareHeaderNative>>(
                'waveOutPrepareHeader')
            .asFunction(),
        waveOutWrite = _lib
            .lookup<ffi.NativeFunction<_WaveOutWriteNative>>('waveOutWrite')
            .asFunction(),
        waveOutUnprepareHeader = _lib
            .lookup<ffi.NativeFunction<_WaveOutUnprepareHeaderNative>>(
                'waveOutUnprepareHeader')
            .asFunction(),
        waveOutClose = _lib
            .lookup<ffi.NativeFunction<_WaveOutCloseNative>>('waveOutClose')
            .asFunction(),
        waveOutReset = _lib
            .lookup<ffi.NativeFunction<_WaveOutResetNative>>('waveOutReset')
            .asFunction(),
        waveOutSetVolume = _lib
            .lookup<ffi.NativeFunction<_WaveOutSetVolumeNative>>('waveOutSetVolume')
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

typedef _WaveOutOpenNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
  ffi.Uint32 uDeviceID,
  ffi.Pointer<WAVEFORMATEX> pwfx,
  ffi.Pointer<ffi.Void> dwCallback,
  ffi.Pointer<ffi.Void> dwInstance,
  ffi.Uint32 fdwOpen,
);
typedef _WaveOutOpenDart = int Function(
  ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
  int uDeviceID,
  ffi.Pointer<WAVEFORMATEX> pwfx,
  ffi.Pointer<ffi.Void> dwCallback,
  ffi.Pointer<ffi.Void> dwInstance,
  int fdwOpen,
);

typedef _WaveOutGetNumDevsNative = ffi.Uint32 Function();
typedef _WaveOutGetNumDevsDart = int Function();

typedef _WaveOutGetDevCapsWNative = ffi.Uint32 Function(
  ffi.Uint32 uDeviceID,
  ffi.Pointer<WAVEOUTCAPSW> pwoc,
  ffi.Uint32 cbwoc,
);
typedef _WaveOutGetDevCapsWDart = int Function(
  int uDeviceID,
  ffi.Pointer<WAVEOUTCAPSW> pwoc,
  int cbwoc,
);

typedef _WaveOutPrepareHeaderNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  ffi.Uint32 cbwh,
);
typedef _WaveOutPrepareHeaderDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  int cbwh,
);

typedef _WaveOutWriteNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  ffi.Uint32 cbwh,
);
typedef _WaveOutWriteDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  int cbwh,
);

typedef _WaveOutUnprepareHeaderNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  ffi.Uint32 cbwh,
);
typedef _WaveOutUnprepareHeaderDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Pointer<WAVEHDR> pwh,
  int cbwh,
);

typedef _WaveOutCloseNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
);
typedef _WaveOutCloseDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
);

typedef _WaveOutResetNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
);
typedef _WaveOutResetDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
);

typedef _WaveOutSetVolumeNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
  ffi.Uint32 dwVolume,
);
typedef _WaveOutSetVolumeDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
  int dwVolume,
);

typedef _WaveOutPauseNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
);
typedef _WaveOutPauseDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
);

typedef _WaveOutRestartNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> hwo,
);
typedef _WaveOutRestartDart = int Function(
  ffi.Pointer<ffi.Void> hwo,
);

class _CoreAudioBindings {
  _CoreAudioBindings() {
    final lib = ffi.DynamicLibrary.process();
    open = lib
        .lookup<ffi.NativeFunction<_CoreAudioOpenNative>>('phonolite_audio_open')
        .asFunction();
    close = lib
        .lookup<ffi.NativeFunction<_CoreAudioCloseNative>>('phonolite_audio_close')
        .asFunction();
    write = lib
        .lookup<ffi.NativeFunction<_CoreAudioWriteNative>>('phonolite_audio_write')
        .asFunction();
    setVolume = lib
        .lookup<ffi.NativeFunction<_CoreAudioSetVolumeNative>>(
            'phonolite_audio_set_volume')
        .asFunction();
    pause = lib
        .lookup<ffi.NativeFunction<_CoreAudioPauseNative>>('phonolite_audio_pause')
        .asFunction();
    resume = lib
        .lookup<ffi.NativeFunction<_CoreAudioResumeNative>>('phonolite_audio_resume')
        .asFunction();
    collectDoneSamples = lib
        .lookup<ffi.NativeFunction<_CoreAudioCollectDoneNative>>(
            'phonolite_audio_collect_done_samples')
        .asFunction();
    isIdle = lib
        .lookup<ffi.NativeFunction<_CoreAudioIsIdleNative>>('phonolite_audio_is_idle')
        .asFunction();
    getOutputDeviceCount = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceCountNative>>(
            'phonolite_audio_get_output_device_count')
        .asFunction();
    getOutputDeviceId = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceIdNative>>(
            'phonolite_audio_get_output_device_id')
        .asFunction();
    _getOutputDeviceName = lib
        .lookup<ffi.NativeFunction<_CoreAudioDeviceNameNative>>(
            'phonolite_audio_get_output_device_name')
        .asFunction();
  }

  static const int _nameBufferLen = 256;
  late final _CoreAudioOpenDart open;
  late final _CoreAudioCloseDart close;
  late final _CoreAudioWriteDart write;
  late final _CoreAudioSetVolumeDart setVolume;
  late final _CoreAudioPauseDart pause;
  late final _CoreAudioResumeDart resume;
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

typedef _CoreAudioOpenNative = ffi.Pointer<ffi.Void> Function(
  ffi.Int32 sampleRate,
  ffi.Int32 channels,
  ffi.Int32 deviceId,
);
typedef _CoreAudioOpenDart = ffi.Pointer<ffi.Void> Function(
  int sampleRate,
  int channels,
  int deviceId,
);

typedef _CoreAudioCloseNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
);
typedef _CoreAudioCloseDart = void Function(
  ffi.Pointer<ffi.Void> handle,
);

typedef _CoreAudioWriteNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Int16> samples,
  ffi.Int32 sampleCount,
);
typedef _CoreAudioWriteDart = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Int16> samples,
  int sampleCount,
);

typedef _CoreAudioSetVolumeNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Float volume,
);
typedef _CoreAudioSetVolumeDart = void Function(
  ffi.Pointer<ffi.Void> handle,
  double volume,
);

typedef _CoreAudioPauseNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
);
typedef _CoreAudioPauseDart = void Function(
  ffi.Pointer<ffi.Void> handle,
);

typedef _CoreAudioResumeNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> handle,
);
typedef _CoreAudioResumeDart = void Function(
  ffi.Pointer<ffi.Void> handle,
);

typedef _CoreAudioCollectDoneNative = ffi.Int64 Function(
  ffi.Pointer<ffi.Void> handle,
);
typedef _CoreAudioCollectDoneDart = int Function(
  ffi.Pointer<ffi.Void> handle,
);

typedef _CoreAudioIsIdleNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
);
typedef _CoreAudioIsIdleDart = int Function(
  ffi.Pointer<ffi.Void> handle,
);

typedef _CoreAudioDeviceCountNative = ffi.Int32 Function();
typedef _CoreAudioDeviceCountDart = int Function();

typedef _CoreAudioDeviceIdNative = ffi.Uint32 Function(
  ffi.Int32 index,
);
typedef _CoreAudioDeviceIdDart = int Function(
  int index,
);

typedef _CoreAudioDeviceNameNative = ffi.Int32 Function(
  ffi.Uint32 deviceId,
  ffi.Pointer<ffi.Char> buffer,
  ffi.Int32 bufferLen,
);
typedef _CoreAudioDeviceNameDart = int Function(
  int deviceId,
  ffi.Pointer<ffi.Char> buffer,
  int bufferLen,
);

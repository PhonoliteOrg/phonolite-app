import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show IsolateNameServer;

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'server_connection.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

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
    void Function(Duration position, Duration bufferedAhead, double? bitrateKbps)? onStats,
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
  final void Function(Duration position, Duration bufferedAhead, double? bitrateKbps)?
      _onStats;
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
        final handler = _onStats;
        if (handler != null) {
          handler(
            Duration(milliseconds: positionMs),
            Duration(milliseconds: bufferedMs),
            (message['bitrate_kbps'] as num?)?.toDouble(),
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
    _workerPort?.send({'cmd': 'stop'});
  }

  void setVolume(double value) {
    if (!_ready.isCompleted) {
      _ready.future.then((_) => _workerPort?.send({'cmd': 'volume', 'value': value}));
      return;
    }
    _workerPort?.send({'cmd': 'volume', 'value': value});
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
    if (!_ready.isCompleted) {
      _ready.future.then((_) => _workerPort?.send({
            'cmd': 'device',
            'device_id': deviceId,
          }));
      return;
    }
    _workerPort?.send({
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
    if (!_ready.isCompleted) {
      _ready.future.then((_) => _workerPort?.send({'cmd': 'pause'}));
      return;
    }
    _paused = true;
    _workerPort?.send({'cmd': 'pause'});
  }

  void resume() {
    if (!_ready.isCompleted) {
      _ready.future.then((_) => _workerPort?.send({'cmd': 'resume'}));
      return;
    }
    _paused = false;
    _workerPort?.send({'cmd': 'resume'});
  }

  bool get hasActivePlayer => _active;

  bool get isPaused => _paused;

  Future<void> playTrack({
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
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
      'device_id': _outputDeviceId,
    });
  }
}

class _AudioWorkerEngine {
  _AudioWorkerEngine({
    http.Client? client,
    required void Function(Map<String, dynamic> message) send,
  })  : _client = client ?? http.Client(),
        _send = send;

  final http.Client _client;
  final void Function(Map<String, dynamic> message) _send;
  int _playbackId = 0;
  _NativeAudioPlayer? _player;
  Timer? _statsTimer;
  int _queuedSamples = 0;
  int _playedSamples = 0;
  int _bytesReceived = 0;
  int _lastBitrateBytes = 0;
  DateTime? _lastBitrateAt;
  DateTime? _playbackStart;
  DateTime? _pauseStart;
  Duration _pausedDuration = Duration.zero;
  bool _paused = false;
  bool _userPaused = false;
  bool _autoPausedForBuffer = false;
  Duration _startOffset = Duration.zero;
  int _sampleRate = 48000;
  int _channels = 2;
  double _volume = 1.0;
  int _outputDeviceId = kDefaultOutputDeviceId;
  bool _prebuffering = false;
  bool _flushingPrebuffer = false;
  bool _streamEnded = false;
  bool _reportedStart = false;
  int _prebufferSamples = 0;
  final List<Int16List> _prebufferChunks = [];
  final List<Int16List> _writeBuffer = [];
  int _writeBufferSamples = 0;
  int _writeChunkSamples = 0;
  final List<Int16List> _pausedBuffer = [];
  int _pausedBufferSamples = 0;
  int _pausedBufferMaxSamples = 0;
  static final double _prebufferSeconds = Platform.isIOS ? 6.0 : 10.0;
  static const double _rebufferMinSeconds = 1.0;
  static const double _rebufferTargetSeconds = 8.0;
  static const int _writeChunkMs = 200;
  static const double _pausedBufferMaxSeconds = 60.0;

  void dispose() {
    stop();
  }

  void stop() {
    _playbackId++;
    final player = _player;
    _player = null;
    if (player != null) {
      player.dispose();
    }
    _stopStats();
    _queuedSamples = 0;
    _playedSamples = 0;
    _bytesReceived = 0;
    _lastBitrateBytes = 0;
    _lastBitrateAt = null;
    _playbackStart = null;
    _pauseStart = null;
    _pausedDuration = Duration.zero;
    _paused = false;
    _userPaused = false;
    _autoPausedForBuffer = false;
    _startOffset = Duration.zero;
    _prebuffering = false;
    _flushingPrebuffer = false;
    _streamEnded = false;
    _reportedStart = false;
    _prebufferSamples = 0;
    _prebufferChunks.clear();
    _writeBuffer.clear();
    _writeBufferSamples = 0;
    _writeChunkSamples = 0;
    _pausedBuffer.clear();
    _pausedBufferSamples = 0;
    _pausedBufferMaxSamples = 0;
    _send({'type': 'state', 'active': false, 'paused': false});
  }

  bool get hasActivePlayer => _player != null;

  bool get isPaused => _paused;

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
    _send({'type': 'state', 'active': _player != null, 'paused': _paused});
  }

  void setOutputDevice(int deviceId) {
    _outputDeviceId = deviceId;
  }

  Future<void> playTrack({
    required String trackId,
    required String trackTitle,
    required String baseUrl,
    required String token,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
  }) async {
    stop();
    final playbackId = ++_playbackId;
    _startOffset = startOffset;
    _paused = false;
    _pauseStart = null;
    _pausedDuration = Duration.zero;
    _userPaused = false;
    _autoPausedForBuffer = false;
    _flushingPrebuffer = false;
    _streamEnded = false;
    _reportedStart = false;
    _playedSamples = 0;
    _bytesReceived = 0;
    _lastBitrateBytes = 0;
    _lastBitrateAt = null;

    if (!(Platform.isWindows || Platform.isMacOS || Platform.isIOS)) {
      throw Exception('Audio playback is only implemented for Windows and Apple platforms right now.');
    }

    final url = _buildRawOpusUrl(baseUrl, trackId, settings);
    _log('Opening stream: $url');
    final request = http.Request('GET', Uri.parse(url));
    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await _client.send(request);
    _log('Stream response: HTTP ${response.statusCode}');
    _maybeReportServerInfo(response.headers);
    if (response.headers.isNotEmpty) {
      _log('Stream headers: ${response.headers}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Stream failed: HTTP ${response.statusCode}');
    }

    final reader = _ByteQueue();
    RawOpusHeader? header;
    OpusDecoder? decoder;
    int? maxFrameSize;
    int? pendingFrameLen;
    int preSkipSamples = 0;
    var skipSamples = 0;
    int? headerLen;
    final headerBuilder = BytesBuilder();
    var wroteFirstFrame = false;
    var bytesReceived = 0;
    var framesDecoded = 0;
    var lastLogTime = DateTime.now();
    const logInterval = Duration(seconds: 2);
    var lastFrameLen = 0;
    var decodeErrors = 0;
    var debugFramesLogged = 0;
    var streamEnded = false;

    await for (final chunk in response.stream) {
      if (playbackId != _playbackId) {
        break;
      }
      final data = Uint8List.fromList(chunk);
      bytesReceived += data.length;
      _bytesReceived = bytesReceived;
      reader.add(data);

      while (true) {
        if (header == null) {
          if (headerLen == null) {
            final prefix = reader.read(12);
            if (prefix == null) {
              break;
            }
            headerLen = prefix[10] | (prefix[11] << 8);
            headerBuilder.add(prefix);
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
          header = RawOpusHeader.parse(headerBytes);
          _log(
            'Opus header: ${header.sampleRate} Hz, ${header.channels}ch, frame ${header.frameMs}ms',
          );
          final frameSamples = (header.sampleRate * header.frameMs / 1000).round();
          _log('Opus frame samples per channel: $frameSamples');
          final created = OpusDecoder(
            sampleRate: header.sampleRate,
            channels: header.channels,
          );
          decoder = created;
          maxFrameSize = created.maxFrameSize;
          _log('Opus max frame size: $maxFrameSize');
          preSkipSamples = header.preSkip * header.channels;
          skipSamples = (startOffset.inMilliseconds * header.sampleRate ~/ 1000) *
              header.channels;
          _player = _createPlayer(
            sampleRate: header.sampleRate,
            channels: header.channels,
            deviceId: _outputDeviceId,
          );
          _player?.setVolume(_volume);
          _send({'type': 'state', 'active': true, 'paused': _paused});
          _sampleRate = header.sampleRate;
          _channels = header.channels;
          _writeChunkSamples =
              ((_sampleRate * _channels * _writeChunkMs) / 1000).round();
          _pausedBufferMaxSamples =
              ((_sampleRate * _channels * _pausedBufferMaxSeconds)).round();
          _startStats();
          _prebuffering = true;
          _flushingPrebuffer = false;
          _prebufferSamples = 0;
          _prebufferChunks.clear();
          _writeBuffer.clear();
          _writeBufferSamples = 0;
          _pausedBuffer.clear();
          _pausedBufferSamples = 0;
          continue;
        }

        if (pendingFrameLen == null) {
          final lenBytes = reader.read(2);
          if (lenBytes == null) {
            break;
          }
            pendingFrameLen = lenBytes[0] | (lenBytes[1] << 8);
            if (pendingFrameLen == 0) {
              streamEnded = true;
              _streamEnded = true;
              break;
            }
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
            _log('Warning: samples not multiple of channels (${activeHeader.channels}).');
          }
          final expected = frameHint * activeHeader.channels;
          if (sampleCount != expected) {
            _log('Warning: samples != expected (${expected}).');
          }
        }

        if (preSkipSamples > 0) {
          if (samples.length <= preSkipSamples) {
            preSkipSamples -= samples.length;
            continue;
          }
          final trimmed = samples.sublist(preSkipSamples);
          preSkipSamples = 0;
          final player = _player;
          if (player == null) {
            _log('Audio output not initialized (player is null).');
            return;
          }
          if (_prebuffering) {
            await _stagePrebuffer(trimmed);
          } else {
            await _enqueueSamples(player, trimmed);
          }
          continue;
        }

        if (skipSamples > 0) {
          if (samples.length <= skipSamples) {
            skipSamples -= samples.length;
            continue;
          }
          samples = samples.sublist(skipSamples);
          skipSamples = 0;
        } else {
          // Keep samples as-is.
        }
        final player = _player;
        if (player == null) {
          _log('Audio output not initialized (player is null).');
          return;
        }
        if (_prebuffering) {
          await _stagePrebuffer(samples);
        } else {
          await _enqueueSamples(player, samples);
          if (!wroteFirstFrame) {
            wroteFirstFrame = true;
            _playbackStart ??= DateTime.now();
            _log('Audio playback started.');
            _reportStarted();
          }
        }
      }

      if (streamEnded) {
        break;
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
    if (_prebuffering && _prebufferSamples > 0) {
      _log('Stream ended during prebuffer; flushing remaining audio.');
      _prebuffering = false;
      _flushingPrebuffer = true;
      await _flushPrebuffer();
    }
    if (playbackId == _playbackId) {
      if (_autoPausedForBuffer && _player != null) {
        _player!.resume();
        _autoPausedForBuffer = false;
        _paused = false;
        _pauseStart = null;
        _send({'type': 'state', 'active': _player != null, 'paused': false});
      }
      final player = _player;
      if (player != null) {
        while (!player.isIdle) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          _playedSamples += player.collectDoneSamples();
        }
      }
      _stopStats();
      _queuedSamples = 0;
      _playedSamples = 0;
      _playbackStart = null;
      _pauseStart = null;
      _pausedDuration = Duration.zero;
      _paused = false;
      _prebuffering = false;
      _flushingPrebuffer = false;
      _prebufferSamples = 0;
      _prebufferChunks.clear();
      _writeBuffer.clear();
      _writeBufferSamples = 0;
      _writeChunkSamples = 0;
      _pausedBuffer.clear();
      _pausedBufferSamples = 0;
      _pausedBufferMaxSamples = 0;
      _startOffset = Duration.zero;
      _send({'type': 'complete'});
    }
  }

  String _buildRawOpusUrl(
    String baseUrl,
    String trackId,
    StreamSettings settings,
  ) {
    return '$baseUrl/stream/$trackId/opus/raw?mode=${settings.mode}'
        '&quality=${settings.quality}'
        '&frame_ms=${settings.frameMs}';
  }

  void _log(String message) {
    _send({'type': 'message', 'text': message});
  }

  void _reportStarted() {
    if (_reportedStart) {
      return;
    }
    _reportedStart = true;
    _send({'type': 'started'});
  }

  void _startStats() {
    _stopStats();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final player = _player;
      if (player != null) {
        _playedSamples += player.collectDoneSamples();
      }
      final start = _playbackStart;
      if (start == null) {
        return;
      }
      final now = _paused ? (_pauseStart ?? DateTime.now()) : DateTime.now();
      var elapsed = now.difference(start) - _pausedDuration;
      if (elapsed.isNegative) {
        elapsed = Duration.zero;
      }
      final elapsedSamples =
          (elapsed.inMilliseconds * _sampleRate ~/ 1000) * _channels;
      final basePlayed = _playedSamples > elapsedSamples ? _playedSamples : elapsedSamples;
      final playedSamples = basePlayed.clamp(0, _queuedSamples);
      final buffered = (_queuedSamples - playedSamples).clamp(0, _queuedSamples);
      final samplesPerSecond = _sampleRate * _channels;
      final bufferedMs =
          samplesPerSecond == 0 ? 0 : (buffered * 1000 ~/ samplesPerSecond);
      final bufferedAhead = Duration(milliseconds: bufferedMs);
      final playedMs =
          samplesPerSecond == 0 ? 0 : (playedSamples * 1000 ~/ samplesPerSecond);
      final position = _startOffset + Duration(milliseconds: playedMs);
      _maybeRebuffer(bufferedAhead);
      _send({
        'type': 'stats',
        'position_ms': position.inMilliseconds,
        'buffered_ms': bufferedAhead.inMilliseconds,
        'bitrate_kbps': _currentBitrateKbps(),
      });
    });
  }

  void _maybeReportServerInfo(Map<String, String> headers) {
    final sessionId = headers['x-stream-session-id'];
    final bitrateValue = headers['x-stream-bitrate-kbps'];
    final bitrate = bitrateValue == null ? null : double.tryParse(bitrateValue);
    if (sessionId == null && (bitrate == null || bitrate <= 0)) {
      return;
    }
    _send({
      'type': 'stream_info',
      'session_id': sessionId,
      'bitrate_kbps': bitrate,
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
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

  Int16List _applyVolume(Int16List samples) {
    return samples;
  }

  void pause() {
    if (_paused) {
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    player.pause();
    _paused = true;
    _userPaused = true;
    _pauseStart = DateTime.now();
    _send({'type': 'state', 'active': _player != null, 'paused': true});
  }

  void resume() {
    if (!_paused) {
      return;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    if (_pausedBufferSamples > 0) {
      () async {
        await _flushPausedBuffer(player);
        player.resume();
      }();
    } else {
      player.resume();
    }
    final pausedAt = _pauseStart ?? DateTime.now();
    _pausedDuration += DateTime.now().difference(pausedAt);
    _pauseStart = null;
    _paused = false;
    _userPaused = false;
    _autoPausedForBuffer = false;
    _send({'type': 'state', 'active': _player != null, 'paused': false});
  }

  void _maybeRebuffer(Duration bufferedAhead) {
    if (_streamEnded) {
      if (_autoPausedForBuffer && _player != null) {
        _player!.resume();
        _autoPausedForBuffer = false;
        _paused = false;
        _pauseStart = null;
        _send({'type': 'state', 'active': _player != null, 'paused': false});
      }
      return;
    }
    if (_userPaused) {
      return;
    }
    if (!_autoPausedForBuffer &&
        bufferedAhead.inMilliseconds <= (_rebufferMinSeconds * 1000).round()) {
      final player = _player;
      if (player == null) {
        return;
      }
      player.pause();
      _paused = true;
      _autoPausedForBuffer = true;
      _pauseStart = DateTime.now();
      _send({'type': 'state', 'active': _player != null, 'paused': true});
      return;
    }
    if (_autoPausedForBuffer &&
        bufferedAhead.inMilliseconds >= (_rebufferTargetSeconds * 1000).round()) {
      final player = _player;
      if (player == null) {
        return;
      }
      player.resume();
      final pausedAt = _pauseStart ?? DateTime.now();
      _pausedDuration += DateTime.now().difference(pausedAt);
      _pauseStart = null;
      _paused = false;
      _autoPausedForBuffer = false;
      _send({'type': 'state', 'active': _player != null, 'paused': false});
    }
  }

  Future<void> _stagePrebuffer(Int16List samples) async {
    if (_flushingPrebuffer) {
      _prebufferChunks.add(samples);
      _prebufferSamples += samples.length;
      _queuedSamples += samples.length;
      return;
    }
    _prebufferChunks.add(samples);
    _prebufferSamples += samples.length;
    _queuedSamples += samples.length;
    final target = (_sampleRate * _channels * _prebufferSeconds).round();
    if (_prebufferSamples >= target) {
      _prebuffering = false;
      _flushingPrebuffer = true;
      await _flushPrebuffer();
    }
  }

  Future<void> _flushPrebuffer() async {
    final player = _player;
    if (player == null) {
      _flushingPrebuffer = false;
      return;
    }
    _playbackStart ??= DateTime.now();
    _reportStarted();
    final chunks = List<Int16List>.from(_prebufferChunks);
    _prebufferChunks.clear();
    _prebufferSamples = 0;
    for (final chunk in chunks) {
      await _enqueueSamples(player, chunk, countQueued: false);
    }
    await _flushWriteBuffer(player);
    if (_playbackStart == null) {
      _playbackStart = DateTime.now();
      _log('Audio playback started.');
    }
    _flushingPrebuffer = false;
  }

  Future<void> _enqueueSamples(
    _NativeAudioPlayer player,
    Int16List samples, {
    bool countQueued = true,
  }) async {
    if (countQueued) {
      _queuedSamples += samples.length;
    }
    if (_paused) {
      if (_pausedBufferMaxSamples > 0 &&
          _pausedBufferSamples + samples.length > _pausedBufferMaxSamples) {
        _log('Paused buffer at capacity; skipping additional samples.');
        return;
      }
      _pausedBuffer.add(samples);
      _pausedBufferSamples += samples.length;
      return;
    }
    if (_writeChunkSamples <= 0) {
      _playbackStart ??= DateTime.now();
      await player.write(samples);
      return;
    }
    _writeBuffer.add(samples);
    _writeBufferSamples += samples.length;
    if (_writeBufferSamples >= _writeChunkSamples) {
      _playbackStart ??= DateTime.now();
      final merged = _mergeWriteBuffer();
      await player.write(merged);
    }
  }

  Future<void> _flushPausedBuffer(_NativeAudioPlayer player) async {
    if (_pausedBufferSamples == 0) {
      return;
    }
    // Snapshot to avoid concurrent modification while new samples arrive.
    final pending = List<Int16List>.from(_pausedBuffer);
    _pausedBuffer.clear();
    _pausedBufferSamples = 0;
    if (_writeChunkSamples <= 0) {
      for (final chunk in pending) {
        await player.write(chunk);
      }
      return;
    }
    for (final chunk in pending) {
      _writeBuffer.add(chunk);
      _writeBufferSamples += chunk.length;
      if (_writeBufferSamples >= _writeChunkSamples) {
        final merged = _mergeWriteBuffer();
        await player.write(merged);
      }
    }
    await _flushWriteBuffer(player);
  }

  Future<void> _flushWriteBuffer(_NativeAudioPlayer player) async {
    if (_writeBufferSamples == 0) {
      return;
    }
    final merged = _mergeWriteBuffer();
    await player.write(merged);
  }

  Int16List _mergeWriteBuffer() {
    final total = _writeBufferSamples;
    final out = Int16List(total);
    var offset = 0;
    for (final chunk in _writeBuffer) {
      out.setAll(offset, chunk);
      offset += chunk.length;
    }
    _writeBuffer.clear();
    _writeBufferSamples = 0;
    return out;
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
        await engine.playTrack(
          trackId: message['track_id']?.toString() ?? '',
          trackTitle: message['track_title']?.toString() ?? '',
          baseUrl: message['base_url']?.toString() ?? '',
          token: message['token']?.toString() ?? '',
          settings: StreamSettings(
            mode: message['mode']?.toString() ?? 'auto',
            quality: message['quality']?.toString() ?? 'high',
            frameMs: (message['frame_ms'] as num?)?.toInt() ?? 60,
          ),
          startOffset: Duration(milliseconds: (message['start_ms'] as num?)?.toInt() ?? 0),
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
      final result = _bindings.write(handle, dataPtr, samples.length);
      if (result != 0) {
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

part of 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

class _PlaybackSession
    with
        _AudioListeningSessionFacade,
        _AudioOutputConfigurationFacade,
        _AudioSeekCoordinatorFacade,
        _OpusDecodePipelineFacade,
        _RemoteAudioSourceFacade,
        _AudioTelemetryFacade,
        _LocalAudioSourceFacade,
        _AdaptiveAudioBufferPolicyFacade,
        _PcmOutputPumpFacade {
  static const double _prebufferSecondsLocal = 0.1;
  static const double _rebufferMinSecondsLocal = 0.04;
  static const double _rebufferTargetSecondsLocal = 0.15;
  static const double _seekStartSeconds = 0.05;
  static const double _seekCatchupMinSeconds = 0.2;
  static const double _seekCatchupTargetSeconds = 0.4;
  static const int _pumpChunkMs = 40;
  static const bool _serverBackpressureEnabled = true;
  static const int _quicStatsLogIntervalMs = 2000;

  @override
  late final _PcmOutputPump _ownerPump;
  @override
  late final _AudioOutputConfiguration _ownerOutput;
  @override
  late final _AdaptiveAudioBufferPolicy _ownerBuffer;
  @override
  late final _LocalAudioSource _ownerLocal;
  @override
  late final _AudioTelemetry _ownerTelemetry;
  @override
  late final _RemoteAudioSource _ownerRemote;
  @override
  late final _OpusDecodePipeline _ownerDecoder;
  @override
  late final _AudioSeekCoordinator _ownerSeek;
  @override
  late final _AudioListeningSession _ownerListening;
  late final ListeningRecorder _listening;
  Future<void>? _stopCompletion;
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
  final AudioPcmOutput Function(int sampleRate, int channels, int deviceId)? _outputFactory;
  double _volume;
  int _outputDeviceId;
  int _outputEpoch = 0;
  bool _stopRequested = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _autoPaused = false;
  QuicClient? _quic;
  OpusDecoder? _decoder;
  LocalAudioDecoder? _localDecoder;
  AudioPcmOutput? _player;
  PcmRingBuffer? _buffer;

  _PlaybackSession.remote({
    required void Function(QuicClient) releaseConnection,
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
    required this.quickStart,
    required bool initialPaused,
    required double volume,
    required int outputDeviceId,
    QuicClient? reusableConnection,
    this.serverPin = '',
    Map<String, dynamic>? listeningContext,
    OpusDecoder Function(int sampleRate, int channels)? decoderFactory,
    AudioPcmOutput Function(int sampleRate, int channels, int deviceId)? outputFactory,
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
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerPump = _PcmOutputPump(this);
    _ownerOutput = _AudioOutputConfiguration(this);
    _ownerBuffer = _AdaptiveAudioBufferPolicy(this);
    _ownerLocal = _LocalAudioSource(this);
    _ownerTelemetry = _AudioTelemetry(this);
    _ownerRemote = _RemoteAudioSource(this);
    _ownerDecoder = _OpusDecodePipeline(this);
    _ownerSeek = _AudioSeekCoordinator(this);
    _ownerListening = _AudioListeningSession(this);

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
    AudioPcmOutput Function(int sampleRate, int channels, int deviceId)? outputFactory,
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
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerPump = _PcmOutputPump(this);
    _ownerOutput = _AudioOutputConfiguration(this);
    _ownerBuffer = _AdaptiveAudioBufferPolicy(this);
    _ownerLocal = _LocalAudioSource(this);
    _ownerTelemetry = _AudioTelemetry(this);
    _ownerRemote = _RemoteAudioSource(this);
    _ownerDecoder = _OpusDecodePipeline(this);
    _ownerSeek = _AudioSeekCoordinator(this);
    _ownerListening = _AudioListeningSession(this);

    _userPaused = initialPaused;
    _paused = initialPaused;
    _listening = ListeningRecorder(
      emit: (event) => _send({'type': 'listening_segment', 'event': event}),
      playbackId: playbackId,
      context: listeningContext,
    );
  }

  bool get _isLocalFile => localFilePath != null;

  bool get _isActive => !_stopRequested && _playbackId == _getPlaybackId();

  QuicClient? takeConnection(String key, String nextTrackId) {
    if (_isLocalFile || trackId == nextTrackId || '$baseUrl|$quicPort|$token|$serverPin' != key) {
      return null;
    }

    final client = _quic;

    _quic = null;

    return client;
  }

  Future<void> requestStop({String outcome = 'cancelled'}) => _stopCompletion ??= _stopPlayback(outcome);

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

  Future<void> run() async {
    var completed = false;

    try {
      await _runPlayback();
      completed = _isActive;
    } catch (err) {
      _log('Playback failed: $err');

      final rejected = err is AudioSourceRejected;

      _sendPlaybackMessage({'type': 'state', 'active': false, 'paused': false, if (rejected) 'source_rejected': true});

      if (rejected) {
        _failSeek('source_rejected');
      }
    } finally {
      try {
        if (_stopCompletion != null) {
          await _stopCompletion;
        }
      } finally {
        _listening.flush(endReason: completed ? 'finished' : 'interrupted');
        _stopStats();

        try {
          _decoder?.dispose();
          _decoder = null;

          _localDecoder?.close();
          _localDecoder = null;

          await _player?.dispose();
        } finally {
          _player = null;
          _playerSampleRate = null;
          _playerChannels = null;
          _playerDeviceId = null;

          final connection = _quic;

          _quic = null;

          if (completed && connection != null && _releaseConnection != null) {
            _releaseConnection(connection);
          } else {
            connection?.close();
          }
        }
      }
    }
  }

  Future<void> _disposeReplacedOutput(AudioPcmOutput player) async {
    try {
      player.pause();

      if (_listening.enabled) {
        await _collectListeningSamples(player);
      }
    } catch (_) {}

    try {
      await player.dispose();
    } finally {
      _listening.flush();
    }
  }

  void _sendPlaybackMessage(Map<String, dynamic> message) {
    _send({'playback_id': _playbackId, ...message});
  }

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

    try {
      if (player != null) {
        try {
          player.pause();

          if (_listening.enabled) {
            await _collectListeningSamples(player);
          }
        } catch (_) {}

        await player.dispose();
      }
    } finally {
      final endReason = switch (outcome) {
        'superseded' => 'skipped',
        'cancelled' => 'stopped',
        _ => 'interrupted',
      };

      _listening.flush(endReason: endReason);
      _playerSampleRate = null;
      _playerChannels = null;
      _playerDeviceId = null;

      _quic?.close();
      _quic = null;
    }
  }

  Future<void> _runPlayback() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) {
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

    final int httpPort;

    if (uri.hasPort) {
      httpPort = uri.port;
    } else {
      httpPort = uri.scheme == 'https' ? 443 : 80;
    }

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

      quic = QuicClient.connect(host: host, port: port, token: token, serverPin: serverPin);
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

  void _log(String message) {
    _sendPlaybackMessage({'type': 'message', 'text': message});
  }
}

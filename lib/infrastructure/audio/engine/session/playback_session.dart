part of '../audio_engine.dart';

class _PlaybackSession
    with
        _AudioListeningSessionFacade,
        _AudioOutputConfigurationFacade,
        _AudioSeekCoordinatorFacade,
        _OpusDecodePipelineFacade,
        _RemoteAudioSourceFacade,
        _AudioTelemetryFacade,
        _FileAudioSourceFacade,
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
  late final _FileAudioSource _ownerFile;
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
  final Duration transportProgressTimeout;
  final AudioNetworkHistory? networkHistory;
  final AudioAutoQualityHistory? autoQualityHistory;
  int _networkRouteGeneration;
  late AudioAutoQualityScope _autoQualityScope = _qualityScope();
  final String? localFilePath;
  final void Function(QuicClient)? _releaseConnection;
  final QuicClient Function()? _connectionFactory;
  final OpusDecoder Function(int sampleRate, int channels)? _decoderFactory;
  final AudioFileDecoder Function(Uri url, Duration startOffset)? _fileDecoderFactory;
  final AudioPcmOutput Function(int sampleRate, int channels, int deviceId)? _outputFactory;
  final _GaplessSourceOutput? _gaplessSource;
  final Duration Function()? _autoOriginalNow;
  late final _AutoOriginalSource _ownerOriginal = _AutoOriginalSource(this);
  double _volume;
  int _outputDeviceId;
  int _outputEpoch = 0;
  bool _stopRequested = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _autoPaused = false;
  QuicClient? _quic;
  OpusDecoder? _decoder;
  AudioFileDecoder? _fileDecoder;
  int _sourceBitDepth = 16;
  int _pcmBitsPerSample = 16;
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
    this.transportProgressTimeout = const Duration(seconds: 15),
    required bool initialPaused,
    required double volume,
    required int outputDeviceId,
    this.networkHistory,
    this.autoQualityHistory,
    this._networkRouteGeneration = 0,
    QuicClient? reusableConnection,
    QuicClient Function()? connectionFactory,
    this.serverPin = '',
    Map<String, dynamic>? listeningContext,
    OpusDecoder Function(int sampleRate, int channels)? decoderFactory,
    AudioFileDecoder Function(Uri url, Duration startOffset)? fileDecoderFactory,
    AudioPcmOutput Function(int sampleRate, int channels, int deviceId)? outputFactory,
    _GaplessSourceOutput? gaplessSource,
    this._autoOriginalNow,
  }) : _send = send,
       _playbackId = playbackId,
       _getPlaybackId = getPlaybackId,
       _volume = volume,
       _outputDeviceId = outputDeviceId,
       localFilePath = null,
       _decoderFactory = decoderFactory,
       _fileDecoderFactory = fileDecoderFactory,
       _outputFactory = outputFactory,
       _gaplessSource = gaplessSource,
       _quic = reusableConnection,
       _connectionFactory = connectionFactory,
       _releaseConnection = releaseConnection {
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerPump = _PcmOutputPump(this);
    _ownerOutput = _AudioOutputConfiguration(this);
    _ownerBuffer = _AdaptiveAudioBufferPolicy(this);
    _ownerFile = _FileAudioSource(this);
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
    AudioFileDecoder Function(Uri url, Duration startOffset)? fileDecoderFactory,
    _GaplessSourceOutput? gaplessSource,
  }) : _send = send,
       _playbackId = playbackId,
       _getPlaybackId = getPlaybackId,
       baseUrl = '',
       token = '',
       serverPin = '',
       quicPort = null,
       settings = const StreamSettings(mode: 'local', quality: 'source'),
       _autoOriginalNow = null,
       queueTrackIds = const <String>[],
       quickStart = true,
       _volume = volume,
       _outputDeviceId = outputDeviceId,
       localFilePath = filePath,
       networkHistory = null,
       autoQualityHistory = null,
       _networkRouteGeneration = 0,
       transportProgressTimeout = const Duration(seconds: 15),
       _decoderFactory = null,
       _fileDecoderFactory = fileDecoderFactory,
       _outputFactory = outputFactory,
       _gaplessSource = gaplessSource,
       _connectionFactory = null,
       _releaseConnection = null {
    // Create state owners in the same zone as the parent and before UI subscriptions.
    _ownerPump = _PcmOutputPump(this);
    _ownerOutput = _AudioOutputConfiguration(this);
    _ownerBuffer = _AdaptiveAudioBufferPolicy(this);
    _ownerFile = _FileAudioSource(this);
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

  bool get _isFileSource => _isLocalFile || settings.isOriginal;

  bool get _isActive => !_stopRequested && _playbackId == _getPlaybackId();

  AudioAutoQualityScope _qualityScope() => AudioAutoQualityHistory.scope(
    endpoint: '$baseUrl|$quicPort',
    token: token,
    serverPin: serverPin,
    routeGeneration: _networkRouteGeneration,
  );

  void notifyNetworkChange(int generation) {
    if (!_isActive || _isLocalFile) {
      return;
    }

    if (generation > _networkRouteGeneration) {
      _networkRouteGeneration = generation;
      _autoQualityScope = _qualityScope();
    }

    if (settings.isOriginal) {
      _ownerFile.notifyNetworkChange(generation);
    } else {
      _ownerRemote.notifyNetworkChange(generation);
      _ownerOriginal.notifyNetworkChange(generation);
    }
  }

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
      if (_userPaused && _paused && _isActive && identical(player, _player)) {
        _sendPlaybackMessage({'type': 'state', 'active': true, 'paused': true});
      }
    }
  }

  void resume() {
    _userPaused = false;
    _reportBuffer(force: true);

    if (_autoPaused) {
      _maybeRebuffer(_ownerBuffer._bufferedAudioSamples());

      return;
    }

    if (!_paused) {
      return;
    }

    _paused = false;
    final player = _player;

    if (player != null && _startedPlayback) {
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

      final source = _gaplessSource;
      if (source != null && (!source._isPrepared || source._announced)) {
        // A failed audible source cannot authorize its successor to render
        // while decoder/file cleanup or UI recovery is still pending.
        await source.abort();
      }

      final rejected =
          err is AudioSourceRejected ||
          err is ServerIdentityChangedException ||
          (err is QuicException && err.kind != QuicFailureKind.none && err.kind != QuicFailureKind.transport);

      // Invalidate every producer/pump before releasing native resources. File
      // read failures otherwise leave a detached pump waiting on a disposed output.
      await requestStop(outcome: 'error');

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
        await _ownerOriginal.close();
        _encodedCache.clear();

        try {
          _decoder?.dispose();
          _decoder = null;

          await _fileDecoder?.close();
          _fileDecoder = null;

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

      await _fileDecoder?.close();
      _fileDecoder = null;
      await _ownerOriginal.close();
    }
  }

  Future<void> _runPlayback() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isAndroid || Platform.isLinux)) {
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

    if (settings.isOriginal) {
      // The source decoder owns a seekable QUIC byte reader. It shares the PCM
      // buffer, seek coordinator and output timeline with other sources.
      _quic?.close();
      _quic = null;
      await _runOriginalFilePlayback();

      return;
    }

    final uri = Uri.parse(baseUrl);
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;

    _configureBufferProfile(host);

    var quic = _quic ?? _ownerRemote.connect();

    _quic = quic;
    quic.setAdaptiveRangesEnabled(settings.mode == 'auto');

    try {
      _transportRequestId = quic.openTrack(
        trackId: trackId,
        mode: settings.mode,
        quality: settings.quality,
        frameMs: settings.frameMs,
        queue: queueTrackIds,
        startMs: startOffset.inMilliseconds,
      );
    } catch (error) {
      if (_ownerRemote._terminalFailure(quic, error)) {
        throw AudioSourceRejected(error.toString());
      }
      quic.close();

      quic = _ownerRemote.connect();
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

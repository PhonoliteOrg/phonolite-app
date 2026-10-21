part of 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

class _AudioWorkerEngine {
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

  _AudioWorkerEngine({required void Function(Map<String, dynamic> message) send}) : _send = send;

  Future<void> stop({bool notify = true}) {
    if (notify) {
      _startGeneration++;
    }

    final previous = _stopInFlight;
    if (previous != null) {
      return previous;
    }

    final stopping = _stopSession(notify);

    _stopInFlight = stopping;

    void finishStop() {
      if (identical(_stopInFlight, stopping)) {
        _stopInFlight = null;
      }
    }

    return stopping.whenComplete(finishStop);
  }

  Future<void> dispose() async {
    await stop();
  }

  void configureListening(Map<String, dynamic>? context, {bool discardPending = true}) {
    _listeningRevision++;
    _latestListeningContext = context;

    final session = _session;

    if (session != null) {
      unawaited(session.configureListening(context, discardPending: discardPending));
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
      _send({'type': 'state', 'active': false, 'paused': false, 'playback_id': _playbackId});
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
      _send({'type': 'state', 'active': false, 'paused': false, 'playback_id': _playbackId});
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

  Future<void> seekTo(Duration position, {int? playbackId, int requestId = 0}) async {
    if (playbackId != null && playbackId != _playbackId) {
      _send({'type': 'seek_failed', 'request_id': requestId, 'playback_id': playbackId});

      return;
    }

    final session = _session;

    if (session == null) {
      _send({'type': 'seek_failed', 'request_id': requestId, 'playback_id': _playbackId});

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

    if (reusable == null && _idleConnectionKey == key && _idleTrackId != trackId) {
      reusable = _idleConnection;
      _idleConnection = null;
    }

    await stop(notify: false);

    if (generation != _startGeneration) {
      return;
    }

    _playbackId = playbackId;

    void retainConnection(QuicClient client) {
      if (_playbackId != playbackId) {
        client.close();

        return;
      }

      _idleConnection?.close();
      _idleConnection = client;
      _idleConnectionKey = key;
      _idleTrackId = trackId;
    }

    final session = _PlaybackSession.remote(
      send: _send,
      reusableConnection: reusable,
      releaseConnection: retainConnection,
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
      listeningContext: listeningRevision == _listeningRevision ? listeningContext : _latestListeningContext,
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

    if (generation != _startGeneration) {
      return;
    }

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
      listeningContext: listeningRevision == _listeningRevision ? listeningContext : _latestListeningContext,
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

  Future<void> _stopSession(bool notify) async {
    final stoppedPlaybackId = _playbackId;

    _idleConnection?.close();
    _idleConnection = null;

    final previous = _session;

    _session = null;
    await previous?.requestStop(outcome: notify ? 'cancelled' : 'superseded');

    if (notify) {
      _send({'type': 'state', 'active': false, 'paused': false, 'playback_id': stoppedPlaybackId});
    }
  }
}

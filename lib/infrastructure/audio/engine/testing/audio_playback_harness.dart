part of '../audio_engine.dart';

/// Runs the production receiver/cache/decoder/pump with in-memory test adapters.
/// Construction never starts an isolate, device, socket, or server.
@visibleForTesting
class AudioPlaybackHarness {
  late final _PlaybackSession _session;
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
  final StreamController<Map<String, dynamic>> _events = StreamController<Map<String, dynamic>>.broadcast();
  Future<void>? _run;
  int _requestId = 0;

  AudioPlaybackHarness({
    required QuicClient transport,
    required OpusDecoder Function(int sampleRate, int channels) decoderFactory,
    required AudioPcmOutput Function(int sampleRate, int channels, int deviceId) outputFactory,
    bool initialPaused = false,
    Duration startOffset = Duration.zero,
    Map<String, dynamic>? listeningContext,
    Duration transportProgressTimeout = const Duration(seconds: 15),
  }) {
    _session = _PlaybackSession.remote(
      reusableConnection: transport,
      releaseConnection: (_) {},
      send: _recordEvent,
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
      transportProgressTimeout: transportProgressTimeout,
      initialPaused: initialPaused,
      volume: 1,
      outputDeviceId: -1,
      decoderFactory: decoderFactory,
      outputFactory: outputFactory,
      listeningContext: listeningContext,
    );
  }

  AudioPlaybackHarness.local({
    required String filePath,
    required AudioPcmOutput Function(int sampleRate, int channels, int deviceId) outputFactory,
    bool initialPaused = false,
    Duration startOffset = Duration.zero,
    Map<String, dynamic>? listeningContext,
  }) {
    _session = _PlaybackSession.local(
      send: _recordEvent,
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

  /// Exercises Original's source selection and session behavior with an injected
  /// decoder and memory output, without a network listener or audio device.
  AudioPlaybackHarness.original({
    required AudioFileDecoder Function(Uri url, Duration startOffset) decoderFactory,
    required AudioPcmOutput Function(int sampleRate, int channels, int deviceId) outputFactory,
    bool initialPaused = false,
    Duration startOffset = Duration.zero,
    String baseUrl = 'https://source.test/api',
    int? quicPort,
  }) {
    _session = _PlaybackSession.remote(
      releaseConnection: (_) {},
      send: _recordEvent,
      playbackId: 1,
      getPlaybackId: () => 1,
      trackId: 'track',
      trackTitle: 'Original test',
      baseUrl: baseUrl,
      token: '',
      quicPort: quicPort,
      settings: const StreamSettings(mode: 'original', quality: 'source'),
      startOffset: startOffset,
      queueTrackIds: const [],
      quickStart: true,
      initialPaused: initialPaused,
      volume: 1,
      outputDeviceId: -1,
      fileDecoderFactory: decoderFactory,
      outputFactory: outputFactory,
    );
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  int get cachedBytes => _session._encodedCache.bytes;

  bool get paused => _session._paused;

  bool get autoPaused => _session._autoPaused;

  void start() {
    _run = _session.run();
  }

  /// The same release boundary acknowledged by the production worker.
  Future<void> requestStop() => _session.requestStop();

  Future<void> close() async {
    final stopping = _session.requestStop();

    try {
      await Future.wait<void>([stopping, if (_run != null) _run!]);
    } finally {
      await _events.close();
    }
  }

  int cachedAheadMilliseconds(int positionMs) => _session._encodedCache.bufferedAheadMs(positionMs);

  Future<void> pause() => _session.pause();

  Future<void> configureListening(Map<String, dynamic>? context, {bool discardPending = true}) =>
      _session.configureListening(context, discardPending: discardPending);

  void resume() => _session.resume();

  Future<bool> seek(Duration position) async {
    final requestId = ++_requestId;
    final result = events.firstWhere(
      (event) => event['request_id'] == requestId && (event['type'] == 'seek_ready' || event['type'] == 'seek_failed'),
    );

    await _session.seekTo(position, requestId: requestId);

    return (await result.timeout(const Duration(seconds: 6)))['type'] == 'seek_ready';
  }

  void _recordEvent(Map<String, dynamic> event) {
    messages.add(event);
    _events.add(event);
  }
}

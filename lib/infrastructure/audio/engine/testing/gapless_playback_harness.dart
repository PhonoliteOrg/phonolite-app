part of '../audio_engine.dart';

/// Production worker/timeline with memory sources. Never opens sockets, devices
/// or isolates unless an explicitly supplied test factory chooses to do so.
@visibleForTesting
class GaplessPlaybackHarness {
  final List<Map<String, dynamic>> messages = [];
  late final _AudioWorkerEngine _engine;
  int _playbackId = 0;
  int _seekRequestId = 0;
  GaplessPlaybackHarness({
    required AudioPcmOutput Function(int rate, int channels, int device, int bits, int validBits) outputFactory,
    AudioFileDecoder Function(String trackId, Uri uri, Duration offset)? fileDecoderFactory,
    OpusDecoder Function(int rate, int channels)? decoderFactory,
    QuicClient Function(String trackId)? transportFactory,
    Duration outputProgressTimeout = const Duration(seconds: 5),
    Duration transportProgressTimeout = const Duration(seconds: 15),
  }) {
    _engine = _AudioWorkerEngine(
      send: messages.add,
      outputFactory: outputFactory,
      fileDecoderFactory: fileDecoderFactory,
      decoderFactory: decoderFactory,
      transportFactory: transportFactory,
      outputProgressTimeout: outputProgressTimeout,
      transportProgressTimeout: transportProgressTimeout,
    );
  }
  Future<void> playOriginal(String trackId, {bool initialPaused = false, Map<String, dynamic>? context}) =>
      _engine.playTrack(
        playbackId: ++_playbackId,
        trackId: trackId,
        trackTitle: trackId,
        baseUrl: 'https://source.test/api',
        token: '',
        settings: const StreamSettings(mode: 'original', quality: 'source'),
        initialPaused: initialPaused,
        listeningContext: context,
      );
  Future<void> prepareOriginal(
    String trackId,
    int preparationId, {
    Map<String, dynamic>? context,
    int? afterPreparationId,
  }) => _prepare(
    trackId,
    preparationId,
    const StreamSettings(mode: 'original', quality: 'source'),
    context: context,
    afterPreparationId: afterPreparationId,
  );
  Future<void> playLocal(String trackId, {bool initialPaused = false, Map<String, dynamic>? context}) =>
      _engine.playLocalFile(
        playbackId: ++_playbackId,
        trackId: trackId,
        trackTitle: trackId,
        filePath: '$trackId.flac',
        initialPaused: initialPaused,
        listeningContext: context,
      );
  Future<void> prepareLocal(
    String trackId,
    int preparationId, {
    Map<String, dynamic>? context,
    int? afterPreparationId,
  }) => _prepare(
    trackId,
    preparationId,
    const StreamSettings(mode: 'local', quality: 'source'),
    filePath: '$trackId.flac',
    afterPreparationId: afterPreparationId,
    context: context,
  );
  Future<void> playOpus(
    String trackId, {
    bool initialPaused = false,
    Map<String, dynamic>? context,
    String quality = 'high',
  }) => _engine.playTrack(
    playbackId: ++_playbackId,
    trackId: trackId,
    trackTitle: trackId,
    baseUrl: 'https://source.test/api',
    token: '',
    settings: StreamSettings(mode: 'fixed', quality: quality),
    initialPaused: initialPaused,
    listeningContext: context,
  );
  Future<void> prepareOpus(
    String trackId,
    int preparationId, {
    Map<String, dynamic>? context,
    int? afterPreparationId,
    String quality = 'high',
  }) => _prepare(
    trackId,
    preparationId,
    StreamSettings(mode: 'fixed', quality: quality),
    afterPreparationId: afterPreparationId,
    context: context,
  );
  Future<void> _prepare(
    String track,
    int id,
    StreamSettings settings, {
    String? filePath,
    int? afterPreparationId,
    Map<String, dynamic>? context,
  }) => _engine.prepareNext({
    'playback_id': _playbackId,
    'preparation_id': id,
    'after_preparation_id': afterPreparationId,
    'track_id': track,
    'track_title': track,
    'base_url': 'https://source.test/api',
    'token': '',
    'mode': settings.mode,
    'quality': settings.quality,
    'frame_ms': settings.frameMs,
    'file_path': filePath,
    'listening_context': context,
  });
  Future<void> pause() => _engine.pause();
  void resume() => _engine.resume();
  void configureListening(Map<String, dynamic>? context) => _engine.configureListening(context);
  Future<void> cancel({int? preparationId}) => _engine.cancelPreparedNext(preparationId: preparationId);
  void acknowledge(int preparationId) => _engine.acknowledge(preparationId);
  void setGaplessResampling(bool enabled) => _engine.gaplessResampling = enabled;
  Future<void> seek(Duration position) =>
      _engine.seekTo(position, playbackId: _playbackId, requestId: ++_seekRequestId);
  Future<void> close() async {
    await _engine.dispose();
    await Future.wait(_engine._runs.toList());
  }
}

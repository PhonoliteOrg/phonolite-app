import 'package:phonolite_app/entities/audio_engine.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/server_connection.dart';

/// Test-only inspection of the exact arguments passed to the real engine.
class StreamRequest {
  StreamRequest(this.track, this.connection, this.settings, this.quicPort);
  final Track track;
  final ServerConnection connection;
  final StreamSettings settings;
  final int? quicPort;
}

class ObservedAudioEngine extends AudioEngine {
  ObservedAudioEngine({
    required this.record,
    required this.onRequest,
    super.onMessage,
    super.onStats,
    super.onComplete,
    super.onStarted,
    super.onState,
  });

  final void Function(Map<String, Object?>) record;
  final void Function(StreamRequest) onRequest;

  @override
  Future<void> playTrack({
    required Track track,
    required ServerConnection connection,
    required StreamSettings settings,
    Duration startOffset = Duration.zero,
    List<String> queueTrackIds = const [],
    int? quicPort,
    bool quickStart = true,
    bool initialPaused = false,
  }) {
    onRequest(StreamRequest(track, connection, settings, quicPort));
    record({
      'command': 'play',
      'track_id': track.id,
      'mode': settings.mode,
      'quality': settings.quality,
      'frame_ms': settings.frameMs,
      'start_ms': startOffset.inMilliseconds,
      'initial_paused': initialPaused,
    });
    return super.playTrack(
      track: track,
      connection: connection,
      settings: settings,
      startOffset: startOffset,
      queueTrackIds: queueTrackIds,
      quicPort: quicPort,
      quickStart: quickStart,
      initialPaused: initialPaused,
    );
  }

  @override
  Future<void> playLocalFile({
    required Track track,
    required String filePath,
    String? contentType,
    Duration startOffset = Duration.zero,
    bool initialPaused = false,
  }) {
    record({
      'command': 'play_local',
      'track_id': track.id,
      'start_ms': startOffset.inMilliseconds,
      'initial_paused': initialPaused,
    });
    return super.playLocalFile(
      track: track,
      filePath: filePath,
      contentType: contentType,
      startOffset: startOffset,
      initialPaused: initialPaused,
    );
  }

  @override
  Future<bool> seekTo(Duration position) {
    record({'command': 'seek', 'position_ms': position.inMilliseconds});
    return super.seekTo(position);
  }

  @override
  void pause() {
    record({'command': 'pause'});
    super.pause();
  }

  @override
  void resume() {
    record({'command': 'resume'});
    super.resume();
  }

  @override
  Future<void> stop({bool waitForRelease = false}) {
    record({'command': 'stop'});
    return super.stop(waitForRelease: waitForRelease);
  }

  @override
  void setVolume(double value) {
    record({'command': 'volume', 'value': value});
    super.setVolume(value);
  }

  @override
  void setOutputDevice(int deviceId) {
    record({'command': 'device', 'device_id': deviceId});
    super.setOutputDevice(deviceId);
  }

  @override
  Future<List<OutputDevice>> listOutputDevices() {
    record({'command': 'list_devices'});
    return super.listOutputDevices();
  }
}

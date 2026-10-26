import 'package:phonolite_app/data/models/playback/native_now_playing_snapshot.dart';
import 'package:phonolite_app/data/models/playback/native_remote_command.dart';

class NowPlayingCodec {
  static NativeRemoteCommand decodeCommand(Map<String, dynamic> arguments) {
    final action = switch (arguments['type']?.toString()) {
      'play' => NativeRemoteAction.play,
      'pause' => NativeRemoteAction.pause,
      'next' => NativeRemoteAction.next,
      'prev' => NativeRemoteAction.previous,
      'toggleLike' => NativeRemoteAction.toggleLike,
      'startLibraryShuffle' => NativeRemoteAction.startLibraryShuffle,
      'seek' => NativeRemoteAction.seek,
      _ => NativeRemoteAction.unknown,
    };
    Duration? position;

    if (action == NativeRemoteAction.seek) {
      final rawPosition = arguments['position'];
      final seconds = rawPosition is num ? rawPosition.toDouble() : double.tryParse('$rawPosition');

      if (seconds != null && seconds.isFinite && seconds >= 0 && seconds <= 1.0e9) {
        position = Duration(milliseconds: (seconds * 1000).round());
      }
    }

    return NativeRemoteCommand(action: action, position: position);
  }

  static Map<String, dynamic> encodeSnapshot(NativeNowPlayingSnapshot snapshot) => {
    'epoch': snapshot.epoch,
    'trackId': snapshot.trackId,
    'title': snapshot.title,
    'artist': snapshot.artist,
    'album': snapshot.album,
    'duration': snapshot.duration.inMilliseconds / 1000.0,
    'position': snapshot.position.inMilliseconds / 1000.0,
    'isPlaying': snapshot.isPlaying,
    'liked': snapshot.liked,
    'artworkKey': snapshot.artworkKey,
    if (snapshot.artworkUrl != null) ...{
      'artworkUrl': snapshot.artworkUrl,
      'token': snapshot.token,
      'serverPin': snapshot.serverPin,
    },
    if (snapshot.artworkPath != null) 'artworkPath': snapshot.artworkPath,
    if (snapshot.artworkBytes != null) 'artworkBytes': snapshot.artworkBytes,
  };
}

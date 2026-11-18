import 'package:phonolite_app/application/app/app_controller.dart';

String? playbackQueueSourceLabel(PlaybackState state) {
  switch (state.queueSource) {
    case PlaybackQueueSource.none:
      return null;
    case PlaybackQueueSource.liked:
      return 'LIKED TRACKS';
    case PlaybackQueueSource.playlist:
      return null;
    case PlaybackQueueSource.offline:
      switch (state.localPlaybackSource) {
        case LocalPlaybackSource.none:
          return state.isLocalPlayback ? 'SOURCE: LOCAL' : null;
        case LocalPlaybackSource.library:
          return null;
        case LocalPlaybackSource.liked:
          return 'LIKED TRACKS';
        case LocalPlaybackSource.playlist:
          return null;
      }
  }
}

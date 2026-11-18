import 'package:phonolite_app/application/app/app_controller.dart';

String playbackShuffleLabel(ShuffleMode mode) {
  switch (mode) {
    case ShuffleMode.off:
      return 'Off';
    case ShuffleMode.all:
      return 'Whole Library';
    case ShuffleMode.artist:
      return 'Current Artist';
    case ShuffleMode.album:
      return 'Current Album';
    case ShuffleMode.currentPlaylist:
      return 'Current Playlist';
    case ShuffleMode.custom:
      return 'Custom';
    case ShuffleMode.liked:
      return 'Liked';
  }
}

/// Accessible name of the shuffle toggle; its on/off state is reported separately as toggled.
String playbackShuffleButtonLabel(ShuffleMode mode) {
  return mode == ShuffleMode.off ? 'Shuffle' : 'Shuffle: ${playbackShuffleLabel(mode)}';
}

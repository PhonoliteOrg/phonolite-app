import 'package:phonolite_app/data/models/playback/playback_state.dart';

/// Strict boundary rules shared by device and account playback checkpoints.
abstract final class PlaybackResumeValues {
  static const sourceKinds = {'standalone', 'library', 'liked', 'playlist', 'album', 'artist', 'custom'};
  static const maxQueueTracks = 1000000;

  static Map<String, dynamic> map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid playback object');
    }

    return Map<String, dynamic>.from(value);
  }

  static int integer(Object? value, {int fallback = 0, int maximum = 9007199254740991}) {
    if (value == null) {
      return fallback;
    }

    if (value is! int || value < 0 || value > maximum) {
      throw const FormatException('Invalid playback integer');
    }

    return value;
  }

  static String identifier(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 512 || value.contains('\u0000')) {
      throw const FormatException('Invalid playback identifier');
    }

    return value;
  }

  static List<String> identifiers(Object? value, {int maximum = 128}) {
    if (value == null) {
      return const [];
    }

    if (value is! List || value.length > maximum) {
      throw const FormatException('Invalid playback identifier list');
    }

    return List<String>.unmodifiable(value.map(identifier));
  }

  static ShuffleMode shuffle(Object? value) => switch (value) {
    'off' => ShuffleMode.off,
    'all' => ShuffleMode.all,
    'artist' => ShuffleMode.artist,
    'album' => ShuffleMode.album,
    'custom' => ShuffleMode.custom,
    'liked' => ShuffleMode.liked,
    'current_playlist' => ShuffleMode.currentPlaylist,
    _ => throw const FormatException('Invalid playback shuffle mode'),
  };

  static String shuffleName(ShuffleMode value) =>
      value == ShuffleMode.currentPlaylist ? 'current_playlist' : value.name;
}

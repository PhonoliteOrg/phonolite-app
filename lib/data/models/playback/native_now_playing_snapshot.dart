import 'dart:typed_data';

class NativeNowPlayingSnapshot {
  final int epoch;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final bool liked;
  final String artworkKey;
  final String? artworkUrl;
  final String? token;
  final String? serverPin;
  final String? artworkPath;
  final Uint8List? artworkBytes;

  const NativeNowPlayingSnapshot({
    required this.epoch,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.liked,
    required this.artworkKey,
    this.artworkUrl,
    this.token,
    this.serverPin,
    this.artworkPath,
    this.artworkBytes,
  });
}

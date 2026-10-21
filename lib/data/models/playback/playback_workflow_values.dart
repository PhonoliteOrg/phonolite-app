enum SeekDirection { none, forward, backward }

enum OfflineQueueSource { none, tracks, localLiked, localPlaylist }

class ShuffleContext {
  final String scope;
  final String? playlistId;
  final String? artistId;
  final String? albumId;

  const ShuffleContext({required this.scope, this.playlistId, this.artistId, this.albumId});
}

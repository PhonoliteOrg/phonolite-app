import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';

/// A saved playlist entry remains visible while its source is unavailable.
class LocalPlaylistEntry {
  final String entryKey;
  final String playlistId;
  final int position;
  final Track track;
  final SourceTrackRef? source;
  final String? localTrackId;
  final OfflineDownloadStatus status;
  final bool isPending;
  final String? error;

  const LocalPlaylistEntry({
    required this.entryKey,
    required this.playlistId,
    required this.position,
    required this.track,
    required this.status,
    required this.isPending,
    this.source,
    this.localTrackId,
    this.error,
  });

  bool get isPlayable => !isPending && status == OfflineDownloadStatus.downloaded;
}

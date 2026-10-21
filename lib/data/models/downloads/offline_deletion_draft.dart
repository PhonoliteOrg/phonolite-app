import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';

class OfflineDeletionDraft {
  final OfflineDeletionScope scope;
  final Set<String> pendingFileDeletes = <String>{};
  int removedSourceCount = 0;
  int removedLocalTrackCount = 0;
  int removedMetadataFragmentCount = 0;
  int clearedJobMetadataCount = 0;

  OfflineDeletionDraft({required this.scope});

  OfflineDeletionResult toResult({required int pendingFileDeleteCount, required int pendingArtworkDeleteCount}) {
    return OfflineDeletionResult(
      scope: scope,
      removedSourceCount: removedSourceCount,
      removedLocalTrackCount: removedLocalTrackCount,
      removedMetadataFragmentCount: removedMetadataFragmentCount,
      clearedJobMetadataCount: clearedJobMetadataCount,
      pendingFileDeleteCount: pendingFileDeleteCount,
      pendingArtworkDeleteCount: pendingArtworkDeleteCount,
    );
  }
}

import 'package:phonolite_app/data/models/library/source_track_ref.dart';

/// A recognized recording association, independent of download availability.
class TrackSourceMatch {
  final String localTrackId;
  final SourceTrackRef source;
  final String matchKind;
  final double score;
  final String metadataSignature;
  final DateTime verifiedAt;

  const TrackSourceMatch({
    required this.localTrackId,
    required this.source,
    required this.matchKind,
    required this.score,
    required this.metadataSignature,
    required this.verifiedAt,
  });
}

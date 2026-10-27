import 'package:phonolite_app/data/models/library/track.dart';

/// A track ID is meaningful only within the server that issued it.
class SourceTrackRef {
  final String serverBaseUrl;
  final String serverTrackId;

  const SourceTrackRef({required this.serverBaseUrl, required this.serverTrackId});

  factory SourceTrackRef.fromTrack(Track track, {required String fallbackServerBaseUrl}) => SourceTrackRef(
    serverBaseUrl: track.serverBaseUrl ?? fallbackServerBaseUrl,
    serverTrackId: track.serverTrackId ?? track.id,
  );

  factory SourceTrackRef.fromJson(Map<String, dynamic> json) => SourceTrackRef(
    serverBaseUrl: json['server_base_url']?.toString() ?? '',
    serverTrackId: json['server_track_id']?.toString() ?? '',
  );

  String get key => '$serverBaseUrl\n$serverTrackId';

  bool get isValid => serverBaseUrl.trim().isNotEmpty && serverTrackId.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'server_base_url': serverBaseUrl, 'server_track_id': serverTrackId};

  @override
  bool operator ==(Object other) =>
      other is SourceTrackRef && other.serverBaseUrl == serverBaseUrl && other.serverTrackId == serverTrackId;

  @override
  int get hashCode => Object.hash(serverBaseUrl, serverTrackId);
}

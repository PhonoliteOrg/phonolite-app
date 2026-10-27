class AccountLastTrack {
  final String? trackId;
  final int revision;

  const AccountLastTrack({required this.trackId, required this.revision});

  factory AccountLastTrack.fromJson(Map<String, dynamic> json) =>
      AccountLastTrack(trackId: json['track_id'] as String?, revision: (json['revision'] as num).toInt());
}

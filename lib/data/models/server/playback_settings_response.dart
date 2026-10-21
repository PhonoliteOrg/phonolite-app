class PlaybackSettingsResponse {
  final String repeatMode;

  PlaybackSettingsResponse({required this.repeatMode});

  factory PlaybackSettingsResponse.fromJson(Map<String, dynamic> json) {
    return PlaybackSettingsResponse(repeatMode: json['repeat_mode'] as String? ?? 'off');
  }
}

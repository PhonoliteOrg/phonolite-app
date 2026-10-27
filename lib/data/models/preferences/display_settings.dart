/// Device preferences for the order of local and server collection sections.
class DisplaySettings {
  final bool libraryLocalFirst;
  final bool playlistsLocalFirst;
  final bool likesLocalFirst;

  const DisplaySettings({this.libraryLocalFirst = true, this.playlistsLocalFirst = true, this.likesLocalFirst = true});

  factory DisplaySettings.fromJson(Map<String, dynamic> value) => DisplaySettings(
    libraryLocalFirst: value['libraryLocalFirst'] is bool ? value['libraryLocalFirst'] as bool : true,
    playlistsLocalFirst: value['playlistsLocalFirst'] is bool ? value['playlistsLocalFirst'] as bool : true,
    likesLocalFirst: value['likesLocalFirst'] is bool ? value['likesLocalFirst'] as bool : true,
  );

  DisplaySettings copyWith({bool? libraryLocalFirst, bool? playlistsLocalFirst, bool? likesLocalFirst}) =>
      DisplaySettings(
        libraryLocalFirst: libraryLocalFirst ?? this.libraryLocalFirst,
        playlistsLocalFirst: playlistsLocalFirst ?? this.playlistsLocalFirst,
        likesLocalFirst: likesLocalFirst ?? this.likesLocalFirst,
      );

  Map<String, dynamic> toJson() => {
    'libraryLocalFirst': libraryLocalFirst,
    'playlistsLocalFirst': playlistsLocalFirst,
    'likesLocalFirst': likesLocalFirst,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplaySettings &&
          libraryLocalFirst == other.libraryLocalFirst &&
          playlistsLocalFirst == other.playlistsLocalFirst &&
          likesLocalFirst == other.likesLocalFirst;

  @override
  int get hashCode => Object.hash(libraryLocalFirst, playlistsLocalFirst, likesLocalFirst);
}

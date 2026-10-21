/// The identified artist and individual name credited in a listening snapshot.
class ListeningArtist {
  final String id;
  final String name;

  const ListeningArtist({required this.id, required this.name});

  factory ListeningArtist.fromJson(Map<String, dynamic> json) =>
      ListeningArtist(id: json['id']?.toString() ?? '', name: json['name']?.toString() ?? '');

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is ListeningArtist && runtimeType == other.runtimeType && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(runtimeType, id, name);
}

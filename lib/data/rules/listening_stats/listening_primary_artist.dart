import 'package:phonolite_app/data/models/listening_stats/listening_artist.dart';

/// Reports attribute a listen to one identified main artist, rather than every
/// contributor. Older snapshots may include composers and band members; use a
/// matching saved credit only to recover the main artist's individual name.
ListeningArtist? listeningPrimaryArtist(Map<String, dynamic> metadata) {
  final id = metadata['artist_id']?.toString().trim() ?? '';
  final name = metadata['artist_name']?.toString().trim() ?? '';
  final credits = metadata['artists'] as List? ?? const [];

  if (id.isNotEmpty) {
    for (final credit in credits) {
      final artist = credit as Map;

      if (artist['id']?.toString().trim() == id) {
        final individual = artist['name']?.toString().trim() ?? '';

        if (individual.isNotEmpty) {
          return ListeningArtist(id: id, name: individual);
        }
      }
    }

    return ListeningArtist(id: id, name: name.isEmpty ? id : name);
  }

  if (name.isNotEmpty) {
    return ListeningArtist(id: '', name: name);
  }

  for (final credit in credits) {
    final artist = credit as Map;
    final creditId = artist['id']?.toString().trim() ?? '';
    final creditName = artist['name']?.toString().trim() ?? '';

    if (creditId.isNotEmpty || creditName.isNotEmpty) {
      return ListeningArtist(id: creditId, name: creditName.isEmpty ? creditId : creditName);
    }
  }

  return null;
}

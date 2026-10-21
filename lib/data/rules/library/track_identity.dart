import 'package:phonolite_app/data/models/library/track.dart';

/// Identity used by functional selection, preserving local/server precedence.
String trackSelectionKey(Track track) => track.localId ?? track.serverTrackId ?? track.id;

/// All nonempty aliases by which the same track can appear in stored data.
Set<String> trackIdentityKeys(Track track) => {
  for (final value in [track.id, track.localId, track.serverTrackId])
    if (value?.trim() case final String trimmed when trimmed.isNotEmpty) trimmed,
};

bool trackMatchesAnyIdentity(Track track, Set<String> identities) => trackIdentityKeys(track).any(identities.contains);

import 'package:phonolite_app/data/models/library/track.dart';

/// All nonempty aliases by which the same track can appear in stored data.
Set<String> trackIdentityKeys(Track track) => {
  for (final value in [track.id, track.localId, track.serverTrackId])
    if (value?.trim() case final String trimmed when trimmed.isNotEmpty) trimmed,
};

bool trackMatchesAnyIdentity(Track track, Set<String> identities) => trackIdentityKeys(track).any(identities.contains);

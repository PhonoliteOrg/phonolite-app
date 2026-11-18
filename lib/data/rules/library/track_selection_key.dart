import 'package:phonolite_app/data/models/library/track.dart';

/// Identity used by functional selection, preserving local/server precedence.
String trackSelectionKey(Track track) => track.localId ?? track.serverTrackId ?? track.id;

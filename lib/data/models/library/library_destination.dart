import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';

/// Metadata needed to open a destination. Routing is owned by the UI.
class LibraryDestination {
  final Artist? artist;
  final Album? album;
  final OfflineArtistGroup? localArtist;
  final OfflineAlbumGroup? localAlbum;
  final String artistName;

  const LibraryDestination({this.artist, this.album, this.localArtist, this.localAlbum, this.artistName = ''});
}

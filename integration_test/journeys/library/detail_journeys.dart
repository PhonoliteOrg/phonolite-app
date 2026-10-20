import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/pages/album_detail_screen.dart';
import 'package:phonolite_app/pages/local_album_detail_screen.dart';
import 'package:phonolite_app/widgets/display/album_card.dart';
import 'package:phonolite_app/widgets/display/album_row_tile.dart';
import 'package:phonolite_app/widgets/display/artist_card.dart';
import 'package:phonolite_app/widgets/display/artist_row_tile.dart';

import '../../support/journey.dart';

final detailJourneys = [
  UiJourney(
    id: 'library.album_navigation',
    feature: 'library',
    description: 'Library → artist → album → artist → Library',
    interactions: [
      'library.artist_open',
      'artist.album_open',
      'album.back',
      'artist.back',
    ],
    run: (ui) async {
      await ui.tab('Library');
      final artist = find.byWidgetPredicate(
        (w) => w is ArtistCard || w is ArtistRowTile,
      );
      if (artist.evaluate().isEmpty && ui.scrollable.evaluate().isNotEmpty) {
        await ui.tester.drag(ui.scrollable.first, const Offset(0, -300));
        await ui.animate(800);
      }
      if (artist.evaluate().isEmpty) {
        throw const MissingPrerequisite(
          'No artist is loaded for album navigation',
        );
      }
      await ui.tap(artist.first);
      await ui.waitFor(ui.command('Back to library'));
      await ui.animate(1000);
      final albums = find.byWidgetPredicate(
        (w) => w is AlbumCard || w is AlbumRowTile,
      );
      // Artist detail can load from the server after the route is built.
      await ui.waitUntil(
        () =>
            albums.evaluate().isNotEmpty ||
            find.textContaining('Artist has no').evaluate().isNotEmpty,
        description: 'artist releases',
      );
      if (albums.evaluate().isEmpty) {
        throw const MissingPrerequisite(
          'Selected artist has no browsable albums',
        );
      }
      await ui.tap(albums.first);
      final albumPage = find.byWidgetPredicate(
        (w) => w is AlbumDetailScreen || w is LocalAlbumDetailScreen,
      );
      await ui.waitFor(albumPage);
      await ui.back('Back to artist');
      await ui.back('Back to library');
    },
  ),
];

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/search/widgets/search_result_tile.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import 'app_driver.dart';

/// Library, artist and album steps. Collections may render as cards or rows;
/// the steps find an item in whichever layout is showing.
extension LibrarySteps on AppDriver {
  Finder get _searchField => find.descendant(of: find.byType(SearchHud), matching: find.byType(TextField));

  String get searchText => tester.widget<TextField>(_searchField).controller!.text;

  bool get collectionShowsList => controller.collectionListMode;

  Future<void> search(String query) async {
    await activate(_searchField);
    await tester.enterText(_searchField, query);
    await settle();
  }

  Future<void> openSearchResult(String title) =>
      activate(find.descendant(of: find.byType(SearchResultTile), matching: find.text(title)));

  Future<void> clearSearch() => activate(labelled('Clear search'));

  /// Switches cards/rows with the page's toggle; the preference is shared by
  /// every collection page.
  Future<void> toggleCollectionView({String page = 'Library'}) => activate(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '$page collection view',
      description: '$page collection view toggle',
    ),
  );

  Future<void> openArtist(String name) => activate(
    find.descendant(
      of: find.byWidgetPredicate((widget) => widget is ArtistCard || widget is ArtistRowTile),
      matching: find.text(name),
    ),
  );

  Future<void> openAlbum(String title) => activate(
    find.descendant(
      of: find.byWidgetPredicate((widget) => widget is AlbumCard || widget is AlbumRowTile),
      matching: find.text(title),
    ),
  );

  Future<void> playAlbum() => activate(labelled('Play album'));

  Future<void> playTrack(String title) =>
      activate(find.descendant(of: find.byType(TrackRowTile), matching: find.text(title)));
}

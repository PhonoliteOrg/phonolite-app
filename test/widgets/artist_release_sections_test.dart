import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/formatting/album_labels.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/features/library/widgets/artist_release_sections.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final sharedAlbum = Album(
    id: 'shared',
    title: 'Joint album',
    artist: 'First & Second',
    artistId: 'first',
    artistIds: const ['first', 'second'],
    artistNames: const ['First', 'Second'],
    trackCount: 2,
  );
  final guestAlbum = Album(
    id: 'guest-album',
    title: 'Guest appearance',
    artist: 'Another artist',
    artistId: 'another',
    trackCount: 10,
  );
  final entries = [
    ArtistReleaseContribution(
      album: sharedAlbum,
      trackIds: const ['one', 'two'],
      roles: const ['album_artist'],
    ),
    ArtistReleaseContribution(
      album: guestAlbum,
      trackIds: const ['guest-song'],
      trackTitles: const ['Guest song'],
      roles: const ['featured_artist'],
    ),
  ];

  test('artist summaries show total albums and collaboration counts', () {
    expect(
      artistDetailLabel(
        Artist(id: 'first', name: 'First', albumCount: 2, collabAlbumCount: 1),
      ),
      '3 albums / 1 collab album',
    );
    expect(
      artistDetailLabel(
        Artist(id: 'guest', name: 'Guest', albumCount: 0, collabAlbumCount: 2),
      ),
      '2 albums / 2 collab albums',
    );
    expect(
      artistDetailLabel(
        Artist(
          id: 'composer',
          name: 'Composer',
          albumCount: 0,
          otherCreditCount: 1,
        ),
      ),
      '0 albums',
    );
    expect(
      artistDetailLabel(Artist(id: 'empty', name: 'Empty', albumCount: 0)),
      '0 albums',
    );
  });

  for (final title in ['Collab albums', 'Appears on', 'Other credits']) {
    for (final isListView in [false, true]) {
      for (final width in [390.0, 1280.0]) {
        testWidgets(
          '$title uses ${isListView ? 'rows' : 'cards'} without credit details at $width',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 800);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            Album? opened;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      ArtistContributionSliver(
                        title: title,
                        entries: entries,
                        isListView: isListView,
                        coverFor: (_) => '',
                        onOpen: (album) => opened = album,
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('$title (2)'), findsOneWidget);
            expect(
              find.byType(isListView ? AlbumRowTile : AlbumCard),
              findsNWidgets(2),
            );
            expect(
              find.byType(isListView ? AlbumCard : AlbumRowTile),
              findsNothing,
            );
            expect(find.textContaining('Open full album'), findsNothing);
            expect(find.text('Guest song'), findsNothing);
            expect(find.text('Another artist'), findsNothing);
            await tester.tap(find.text('Guest appearance'));
            expect(opened?.id, 'guest-album');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final isListView in [false, true]) {
    testWidgets(
      '${isListView ? 'row' : 'card'} selection excludes track-only collaborations',
      (tester) async {
        final selectedAlbums = <String>[];
        Album? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ArtistContributionSliver(
                    title: 'Collab albums',
                    entries: entries,
                    isListView: isListView,
                    coverFor: (_) => '',
                    onOpen: (album) => opened = album,
                    selectionMode: true,
                    selectable: (entry) => entry.isAlbumArtist,
                    onSelectionToggle: (entry) =>
                        selectedAlbums.add(entry.album.id),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (isListView) {
          final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
          expect(checkboxes.first.onChanged, isNotNull);
          expect(checkboxes.last.onChanged, isNull);
        }
        await tester.tap(find.text('Joint album'));
        await tester.tap(find.text('Guest appearance'));
        expect(selectedAlbums, ['shared']);
        expect(opened, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

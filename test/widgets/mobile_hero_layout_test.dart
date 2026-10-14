import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/widgets/display/album_art.dart';
import 'package:phonolite_app/widgets/display/album_hero.dart';
import 'package:phonolite_app/widgets/display/artist_avatar.dart';
import 'package:phonolite_app/widgets/display/artist_hero.dart';
import 'package:phonolite_app/widgets/layouts/obsidian_scale.dart';
import 'package:phonolite_app/widgets/ui/compact_hero_details.dart';
import 'package:phonolite_app/widgets/ui/phonolite_icons.dart';

import '../support/widget_test_helpers.dart';

const summary =
    'A complete description of the music and its history, kept available when the details are expanded.';
const genres = ['alternative rock', 'trip hop', 'downtempo'];
const genreLine = 'Alternative Rock • Trip Hop • Downtempo';

void main() {
  setUpAll(configureTestFonts);
  final artist = Artist(
    id: 'artist',
    name: 'An artist with a fairly long name',
    albumCount: 12,
    genres: genres,
    summary: summary,
  );
  final album = Album(
    id: 'album',
    title: 'An album with a fairly long title',
    artist: artist.name,
    artistId: artist.id,
    trackCount: 12,
    year: 2026,
    genres: genres,
    summary: summary,
  );

  Widget header(String kind) => kind == 'artist'
      ? ArtistHero(
          artist: artist,
          coverUrl: null,
          bannerUrl: null,
          headers: const {},
        )
      : AlbumHero(
          album: album,
          coverUrl: '',
          headers: const {},
          actions: IconButton(
            tooltip: 'Edit album',
            onPressed: () {},
            icon: const Icon(PhonoliteIcons.pencil),
          ),
        );

  for (final kind in ['artist', 'album']) {
    for (final width in [320.0, 390.0, 430.0]) {
      for (final textScale in [1.0, 1.4]) {
        testWidgets(
          '$kind mobile header keeps metadata accessible at $width, text scale $textScale',
          (tester) async {
            await _pumpHeader(tester, header(kind), width, textScale);
            final hero = find.byType(kind == 'artist' ? ArtistHero : AlbumHero);
            final label = kind == 'artist' ? 'About artist' : 'Album details';
            final compactHeight = tester.getSize(hero).height;
            if (textScale == 1) expect(compactHeight, lessThan(180));
            expect(find.text(summary), findsNothing);
            expect(find.textContaining(genreLine), findsNothing);
            expect(
              find.text(kind == 'artist' ? '12 albums' : '2026 / 12 tracks'),
              findsOneWidget,
            );
            final disclosure = find.widgetWithText(TextButton, label);
            expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(44));
            if (kind == 'album') {
              expect(find.byTooltip('Edit album'), findsOneWidget);
            }

            await tester.tap(disclosure);
            await tester.pumpAndSettle();
            expect(find.text(summary), findsOneWidget);
            expect(find.text(genreLine), findsOneWidget);
            expect(tester.getSize(hero).height, greaterThan(compactHeight));
            expect(tester.takeException(), isNull);

            await tester.tap(disclosure);
            await tester.pumpAndSettle();
            expect(find.text(summary), findsNothing);
            expect(tester.getSize(hero).height, compactHeight);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }

    testWidgets('$kind desktop header shows metadata by default', (
      tester,
    ) async {
      await _pumpHeader(tester, header(kind), 1280, 1);
      expect(find.byType(CompactHeroDetails), findsNothing);
      expect(find.text(summary), findsOneWidget);
      expect(find.textContaining(genreLine), findsOneWidget);
      if (kind == 'artist') {
        expect(
          tester.widget<ArtistAvatar>(find.byType(ArtistAvatar)).size,
          150,
        );
      } else {
        expect(tester.widget<AlbumArt>(find.byType(AlbumArt)).size, 150);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _pumpHeader(
  WidgetTester tester,
  Widget header,
  double width,
  double textScale,
) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    wrapInTestApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            child: ObsidianScale(scale: width < 640 ? 0.7 : 1, child: header),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_collection_sliver.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';
import 'package:phonolite_app/ui/structures/collections/collection_sliver.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('scrolling page preserves controller, gutter and overlay space', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackContentInset(
            top: 12,
            bottom: 80,
            child: PageScrollView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: const [
                PageSliverBox(
                  top: 16,
                  bottom: 24,
                  child: SizedBox(key: ValueKey('body'), height: 900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scroll.controller, same(controller));
    expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    expect(
      scroll.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
    expect(find.byType(SliverPageTopInset), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('body'))),
      const Offset(20, 28),
    );
    expect(tester.getSize(find.byKey(const ValueKey('body'))).width, 760);
    expect(controller.position.maxScrollExtent, 1032 - 600);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(find.byType(SliverPlaybackInset), findsOneWidget);
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byType(SliverPlaybackInset),
              matching: find.byType(SizedBox),
            ),
          )
          .height,
      80,
    );
    expect(tester.takeException(), isNull);
  });

  for (final listView in [true, false]) {
    testWidgets(
      'empty ${listView ? 'list' : 'grid'} has no invalid child count',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  CollectionSliver<String>(
                    items: const [],
                    isListView: listView,
                    itemBuilder: (_, item, __) => Text(item),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Divider), findsNothing);
      },
    );

    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'artist ${listView ? 'rows' : 'cards'} keep selection and deletion policy at $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final artists = [
            Artist(id: 'available', name: 'Available', albumCount: 1),
            Artist(id: 'deleting', name: 'Deleting', albumCount: 1),
          ];
          final selected = <String>[];
          final opened = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PageScrollView(
                  slivers: [
                    ArtistCollectionSliver<Artist>(
                      items: artists,
                      isListView: listView,
                      artistFor: (artist) => artist,
                      coverFor: (_) => '',
                      onOpen: (artist) => opened.add(artist.id),
                      selectionMode: true,
                      selected: (artist) => artist.id == 'available',
                      isDeleting: (artist) => artist.id == 'deleting',
                      onSelectionToggle: (artist) => selected.add(artist.id),
                    ),
                  ],
                ),
              ),
            ),
          );
          // The deleting item intentionally contains a continuous spinner.
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.text('Available'));
          await tester.tap(find.text('Deleting'), warnIfMissed: false);
          expect(selected, ['available']);
          expect(opened, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

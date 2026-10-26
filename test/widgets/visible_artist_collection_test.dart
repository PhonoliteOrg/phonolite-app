import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/library/visible_artist_loader.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_collection_sliver.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artist_avatar.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets('a visible placeholder gets artwork without opening the artist', (tester) async {
    final source = Artist(id: 'bb', name: 'B.B. King', albumCount: 1);
    final updates = StreamController<Artist>.broadcast(sync: true);
    final changes = ValueNotifier(0);
    final requests = <String>[];
    var opened = false;
    final loader = VisibleArtistLoader(
      fetch: (id) async {
        requests.add(id);
        return source;
      },
      watch: (_) => updates.stream,
      onChanged: () => changes.value++,
    );
    addTearDown(loader.dispose);
    addTearDown(updates.close);
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      wrapInTestApp(
        ValueListenableBuilder(
          valueListenable: changes,
          builder: (context, value, child) => CustomScrollView(
            slivers: [
              ArtistCollectionSliver<Artist>(
                items: [source],
                isListView: false,
                artistFor: loader.resolve,
                coverFor: (artist) => loader.resolve(artist).logoRef,
                onVisibilityChanged: loader.setVisible,
                onOpen: (_) => opened = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(requests, ['bb']);
    expect(tester.widget<ArtistAvatar>(find.byType(ArtistAvatar)).imageUrl, isNull);
    updates.add(source.copyWith(logoRef: '/test/bb-logo.png'));
    await tester.pump();
    expect(tester.widget<ArtistAvatar>(find.byType(ArtistAvatar)).imageUrl, '/test/bb-logo.png');
    expect(opened, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(requests, ['bb']);
    expect(loader.resolve(source).logoRef, isNull);
  });
}

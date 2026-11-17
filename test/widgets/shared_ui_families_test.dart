import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';

import '../support/widget_test_helpers.dart';

void main() {
  for (final family in [
    'album row',
    'artist row',
    'album card',
    'artist card',
  ]) {
    testWidgets('$family preserves selection and deletion interaction', (
      tester,
    ) async {
      var selectionMode = false;
      var selectable = true;
      var deleting = false;
      var opened = 0;
      var toggled = 0;
      late StateSetter update;
      final album = Album(
        id: 'album',
        title: 'Album',
        artist: 'Artist',
        artistId: 'artist',
        trackCount: 2,
      );
      final artist = Artist(id: 'artist', name: 'Artist', albumCount: 1);

      Widget member() {
        void open() => opened++;
        void toggle() => toggled++;
        return switch (family) {
          'album row' => AlbumRowTile(
            album: album,
            coverUrl: '',
            headers: const {},
            onTap: open,
            selectionMode: selectionMode,
            selectable: selectable,
            isDeleting: deleting,
            onSelectionToggle: toggle,
          ),
          'artist row' => ArtistRowTile(
            artist: artist,
            coverUrl: null,
            headers: const {},
            onTap: open,
            selectionMode: selectionMode,
            selectable: selectable,
            isDeleting: deleting,
            onSelectionToggle: toggle,
          ),
          'album card' => AlbumCard(
            album: album,
            coverUrl: '',
            headers: const {},
            onTap: open,
            selectionMode: selectionMode,
            selectable: selectable,
            isDeleting: deleting,
            onSelectionToggle: toggle,
          ),
          _ => ArtistCard(
            artist: artist,
            coverUrl: null,
            headers: const {},
            onTap: open,
            selectionMode: selectionMode,
            selectable: selectable,
            isDeleting: deleting,
            onSelectionToggle: toggle,
          ),
        };
      }

      await tester.pumpWidget(
        wrapInTestApp(
          Center(
            child: SizedBox(
              width: 240,
              height: 260,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return member();
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.text(family.startsWith('album') ? 'Album' : 'Artist'),
      );
      expect(opened, 1);

      update(() => selectionMode = true);
      await tester.pump();
      await tester.tap(
        find.text(family.startsWith('album') ? 'Album' : 'Artist'),
      );
      expect(toggled, 1);
      expect(opened, 1);

      update(() => selectable = false);
      await tester.pump();
      await tester.tap(
        find.text(family.startsWith('album') ? 'Album' : 'Artist'),
      );
      expect(toggled, 1);

      update(() {
        selectionMode = false;
        deleting = true;
      });
      await tester.pump();
      await tester.tap(
        find.text(family.startsWith('album') ? 'Album' : 'Artist'),
      );
      expect(opened, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0.45,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final family in ['HUD', 'Tech', 'Playback']) {
    testWidgets('$family shows touch press and clears cancel and disable', (
      tester,
    ) async {
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        wrapInTestApp(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return _pointerControl(family, enabled ? () {} : null);
              },
            ),
          ),
        ),
      );
      final idle = family == 'Playback'
          ? ObsidianPalette.gold
          : ObsidianPalette.textMuted;
      final active = family == 'Playback' ? Colors.black : ObsidianPalette.gold;
      Color? iconColor() =>
          tester.widget<Icon>(find.byIcon(Icons.play_arrow)).color;
      final center = tester.getCenter(find.byIcon(Icons.play_arrow));
      expect(iconColor(), idle);

      final first = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
      expect(iconColor(), active);
      await first.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(iconColor(), idle);

      final second = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
      expect(iconColor(), active);
      update(() => enabled = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        iconColor()?.toARGB32(),
        ObsidianPalette.textMuted
            .withValues(alpha: family == 'Playback' ? 0.75 : 0.6)
            .toARGB32(),
      );
      update(() => enabled = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(iconColor(), idle);
      await second.cancel();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$family clears a held pointer when disabled and reenabled', (
      tester,
    ) async {
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        wrapInTestApp(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                final action = enabled ? () {} : null;
                return _pointerControl(family, action);
              },
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byIcon(Icons.play_arrow));
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      update(() => enabled = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      update(() => enabled = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.play_arrow)).color,
        family == 'Playback' ? ObsidianPalette.gold : ObsidianPalette.textMuted,
      );
      await gesture.cancel();
      await gesture.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  test('playback button cuts all four corners and clamps oversized cuts', () {
    const size = Size(100, 80);

    for (final fraction in [0.3, 1000.0]) {
      final path = PlaybackOctagonClipper(cutFraction: fraction).getClip(size);

      expect(path.getBounds(), Offset.zero & size);
      for (final corner in const [Offset(1, 1), Offset(99, 1), Offset(99, 79), Offset(1, 79)]) {
        expect(path.contains(corner), isFalse);
      }
      expect(path.contains(const Offset(50, 40)), isTrue);
    }
  });
}

Widget _pointerControl(String family, VoidCallback? action) => switch (family) {
  'HUD' => ObsidianHudIconButton(semanticLabel: 'Play', icon: Icons.play_arrow, onPressed: action),
  'Tech' => TechButton(label: 'Play', icon: Icons.play_arrow, onTap: action),
  _ => PlaybackHudPlayButton(icon: Icons.play_arrow, semanticLabel: 'Play', onPressed: action),
};

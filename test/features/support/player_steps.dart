import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

import 'app_driver.dart';
import 'platform_profile.dart';

/// Player steps. Controls are found on whichever player surface is frontmost.
extension PlayerSteps on AppDriver {
  /// Brings every player control on screen: expands the sheet on compact
  /// layouts; the docked bar already shows them.
  Future<void> openPlayer() async {
    if (profile.playerSurface == PlayerSurface.dockedBar || isPlayerOpen) {
      return;
    }

    final miniBar = find.byType(NowPlayingMiniBar);
    await activate(find.descendant(of: miniBar, matching: find.byType(InkWell)).first);
    expect(find.byType(NowPlayingExpandedSheet), findsOneWidget, reason: 'mini bar should expand the player');
  }

  /// Returns to the underlying page by swiping the sheet down.
  Future<void> closePlayer() async {
    if (!isPlayerOpen) {
      return;
    }

    final sheet = find.byType(NowPlayingExpandedSheet);
    final rect = tester.getRect(sheet);
    await tester.flingFrom(Offset(rect.center.dx, rect.top + 18), Offset(0, rect.height * .8), 1800);
    await settle();
  }

  Future<void> playPause() => activate(_inPlayer(find.byType(PlaybackHudPlayButton)));

  Future<void> next() => activate(_inPlayer(_hudIcon(PhonoliteIcons.skipForward)));

  Future<void> previous() async {
    await openPlayer();
    await activate(_inPlayer(_hudIcon(PhonoliteIcons.skipBack)));
  }

  Future<void> toggleRepeat() async {
    await openPlayer();
    await activate(_inPlayer(_hudIcon(PhonoliteIcons.repeat)));
  }

  Future<void> openShuffleChoices() async {
    await openPlayer();
    await activate(_inPlayer(_hudIcon(PhonoliteIcons.shuffle)));
  }

  Future<void> openOutputPicker() async {
    await openPlayer();
    await activate(_inPlayer(_hudIcon(PhonoliteIcons.speaker)));
  }

  Future<void> pressSpace() => pressKey(LogicalKeyboardKey.space);

  Finder _inPlayer(Finder control) {
    final Finder surface;

    if (isPlayerOpen) {
      surface = find.byType(NowPlayingExpandedSheet);
    } else if (profile.playerSurface == PlayerSurface.dockedBar) {
      surface = find.byType(NowPlayingBar);
    } else {
      surface = find.byType(NowPlayingMiniBar);
    }

    return find.descendant(of: surface, matching: control);
  }

  Finder _hudIcon(IconData icon) =>
      find.byWidgetPredicate((widget) => widget is ObsidianHudIconButton && widget.icon == icon, description: '$icon');
}

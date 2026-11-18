import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/playback_repeat_mode.dart';
import 'package:phonolite_app/data/models/playback/shuffle_mode.dart';

import '../support/feature_scenario.dart';
import '../support/feature_world.dart';
import '../support/platform_profile.dart';
import '../support/player_steps.dart';

/// Player behavior expected on every platform. Nothing here names a
/// platform; profiles and the driver supply the differences.
final playerScenarios = [
  FeatureScenario(
    id: 'player.play_pause',
    description: 'Play starts the loaded track and a second press pauses it',
    covers: ['player.play_pause'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.playPause();
      expect(app.playback.isPlaying, isTrue);

      await app.playPause();
      expect(app.playback.isPlaying, isFalse);
    },
  ),
  FeatureScenario(
    id: 'player.skip',
    description: 'Next advances the queue and Previous returns to the earlier track',
    covers: ['player.next', 'player.previous'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.next();
      expect(app.currentTrack?.title, 'Second Wind');
      app.expectVisible('Second Wind');

      await app.previous();
      expect(app.currentTrack?.title, 'First Light');
      app.expectVisible('First Light');
    },
  ),
  FeatureScenario(
    id: 'player.expand_and_dismiss',
    description: 'The mini bar expands into the full player, which swipes away',
    covers: ['player.expand', 'player.swipe_close'],
    surfaces: {PlayerSurface.expandableSheet},
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.openPlayer();
      expect(app.isPlayerOpen, isTrue);

      await app.closePlayer();
      expect(app.isPlayerOpen, isFalse);
    },
  ),
  FeatureScenario(
    id: 'player.repeat',
    description: 'Repeat toggles between repeating the track and off',
    covers: ['player.repeat'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.toggleRepeat();
      expect(app.playback.repeatMode, PlaybackRepeatMode.one);

      await app.toggleRepeat();
      expect(app.playback.repeatMode, PlaybackRepeatMode.off);
    },
  ),
  FeatureScenario(
    id: 'player.shuffle_dismiss',
    description: 'Shuffle choices open and close without changing the mode',
    covers: ['shuffle.open', 'shuffle.close'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.openShuffleChoices();
      app.expectVisible('Whole Library');

      await app.dismissDialog();
      app.expectNotVisible('Whole Library');
      expect(app.playback.shuffleMode, ShuffleMode.off);
    },
  ),
  FeatureScenario(
    id: 'player.output_select',
    description: 'The output picker lists devices and switches to the chosen one',
    covers: ['output.open', 'output.select'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.openOutputPicker();
      app.expectVisible('Select output device');
      app.expectVisible('Studio Monitors');

      await app.choose('Studio Monitors');
      expect(app.controller.outputDeviceId, 7);
    },
  ),
  FeatureScenario(
    id: 'player.output_dismiss',
    description: 'The output picker closes without changing the output',
    covers: ['output.open', 'output.close'],
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.openOutputPicker();
      await app.dismissDialog();
      app.expectNotVisible('Select output device');
      expect(app.controller.outputDeviceId, -1);
    },
  ),
  FeatureScenario(
    id: 'player.space_toggles',
    description: 'Space toggles playback when no text field or control has focus',
    covers: ['desktop.space'],
    requires: {Capability.keyboardPlayPause},
    world: () => FeatureWorld.pausedQueue,
    run: (app) async {
      await app.pressSpace();
      expect(app.playback.isPlaying, isTrue);

      await app.pressSpace();
      expect(app.playback.isPlaying, isFalse);
    },
  ),
];

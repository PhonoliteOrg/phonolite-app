import 'package:phonolite_app/application/app/app_controller.dart';

/// Accessible name of the repeat toggle; its on/off state is reported separately as toggled.
String playbackRepeatButtonLabel(PlaybackRepeatMode mode) {
  return switch (mode) {
    PlaybackRepeatMode.off => 'Repeat',
    PlaybackRepeatMode.one => 'Repeat: Current Track',
  };
}

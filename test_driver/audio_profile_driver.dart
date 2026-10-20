import 'ui_profile_driver.dart';

Future<void> main() =>
    runProfileDriver(defaultReportRoot: 'build/audio-profile', suite: 'audio');

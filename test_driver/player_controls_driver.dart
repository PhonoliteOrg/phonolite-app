import 'ui_profile_driver.dart';

Future<void> main() => runProfileDriver(
  defaultReportRoot: 'build/player-controls',
  suite: 'audio',
);

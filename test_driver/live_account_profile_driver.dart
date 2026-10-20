import 'ui_profile_driver.dart';

Future<void> main() => runProfileDriver(
  defaultReportRoot: 'build/live-account-profile',
  completionTimeout: const Duration(minutes: 10),
);

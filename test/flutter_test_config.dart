import 'dart:async';

import 'package:phonolite_app/data/storage/windows_app_storage.dart';

/// Runs before every test file.
///
/// Windows storage normally resolves from APPDATA, which bypasses the mocked
/// path provider that keeps other platforms' tests in temporary folders.
/// Without this, Windows test runs read and overwrite the real Phonolite profile.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WindowsAppStorage.environmentOverride = const {};

  await testMain();
}

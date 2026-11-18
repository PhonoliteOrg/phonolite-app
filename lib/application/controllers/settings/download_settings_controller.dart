import 'package:phonolite_app/application/controllers/settings/persisted_settings_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';

/// Owns the default for future downloads; queued jobs retain their own profile.
class DownloadSettingsController extends PersistedSettingsController<DownloadSettings> {
  static final instance = DownloadSettingsController();

  final PreferencesCoordinator preferences;
  bool _loading = false;

  DownloadSettingsController({PreferencesCoordinator? preferences})
    : preferences = preferences ?? PreferencesCoordinator.shared,
      super((preferences ?? PreferencesCoordinator.shared).downloads);

  /// Loads the stored profile once. A read failure is reported and rethrown, because a
  /// download queue must not guess a quality when the device preference is unreadable.
  Future<void> initialize() => initializeOnce(_initialize);

  /// Starts a new load after a failed one; returns the running load if one is in progress.
  Future<void> retryInitialization() {
    if (ready || isDisposed) {
      return Future<void>.value();
    }

    if (_loading) {
      return initialization ?? Future<void>.value();
    }

    resetInitialization();

    return initialize();
  }

  Future<void> setQuality(DownloadQuality quality) => change(DownloadSettings(quality: quality));

  Future<void> _initialize() async {
    _loading = true;

    try {
      await preference.load();
    } finally {
      _loading = false;
    }
  }
}

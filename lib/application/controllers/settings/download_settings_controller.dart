import 'package:phonolite_app/application/controllers/settings/persisted_settings_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/storage/preferences/download_settings_storage.dart';

/// Owns the default for future downloads; queued jobs retain their own profile.
class DownloadSettingsController extends PersistedSettingsController<DownloadSettings> {
  static final instance = DownloadSettingsController();

  final DownloadSettingsStorage _storage;
  bool _loading = false;

  DownloadSettingsController({this._storage = const DownloadSettingsStorage()}) : super(const DownloadSettings());

  @override
  String get settingsLabel => 'download settings';

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

  @override
  Future<void> persist(DownloadSettings next, DownloadSettings previous) => _storage.write(next);

  Future<void> _initialize() async {
    _loading = true;

    try {
      await loadSettings(_storage.read);
    } finally {
      _loading = false;
    }
  }
}

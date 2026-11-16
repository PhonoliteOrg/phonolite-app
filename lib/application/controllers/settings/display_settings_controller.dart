import 'package:phonolite_app/application/controllers/settings/persisted_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/preferences/display_settings_storage.dart';

/// Application-owned display preferences, retained across server connections.
class DisplaySettingsController extends PersistedSettingsController<DisplaySettings> {
  static final instance = DisplaySettingsController();

  final DisplaySettingsStorage _storage;

  DisplaySettingsController({this._storage = const DisplaySettingsStorage()}) : super(const DisplaySettings());

  @override
  String get settingsLabel => 'display settings';

  /// Loads stored preferences once. An unreadable file leaves the defaults in place
  /// and is reported through [error]; startup continues either way.
  Future<void> initialize() => initializeOnce(_initialize);

  Future<void> setLibraryLocalFirst(bool value) => change(settings.copyWith(libraryLocalFirst: value));

  Future<void> setPlaylistsLocalFirst(bool value) => change(settings.copyWith(playlistsLocalFirst: value));

  Future<void> setLikesLocalFirst(bool value) => change(settings.copyWith(likesLocalFirst: value));

  @override
  Future<void> persist(DisplaySettings next, DisplaySettings previous) => _storage.write(next);

  Future<void> _initialize() async {
    if (isDisposed) {
      return;
    }

    try {
      await loadSettings(_storage.read);
    } catch (_) {
      // Reported by loadSettings; the pages keep their local-first defaults.
    }
  }
}

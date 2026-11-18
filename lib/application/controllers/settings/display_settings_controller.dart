import 'package:phonolite_app/application/controllers/settings/persisted_settings_controller.dart';
import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';

/// Application-owned display preferences, retained across server connections.
class DisplaySettingsController extends PersistedSettingsController<DisplaySettings> {
  static final instance = DisplaySettingsController();

  DisplaySettingsController({PreferencesCoordinator? preferences})
    : super((preferences ?? PreferencesCoordinator.shared).display);

  /// Loads stored preferences once. An unreadable file leaves the defaults in place
  /// and is reported through [error]; startup continues either way.
  Future<void> initialize() => initializeOnce(_initialize);

  Future<void> setLibraryLocalFirst(bool value) => change(settings.copyWith(libraryLocalFirst: value));

  Future<void> setPlaylistsLocalFirst(bool value) => change(settings.copyWith(playlistsLocalFirst: value));

  Future<void> setLikesLocalFirst(bool value) => change(settings.copyWith(likesLocalFirst: value));

  Future<void> _initialize() async {
    if (isDisposed) {
      return;
    }

    try {
      await preference.load();
    } on Object catch (_) {
      // The preference reports the read failure and retains its display defaults.
    }
  }
}

import 'package:phonolite_app/application/controllers/playback/custom_shuffle_controller.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

/// An isolated editor draft. Remote changes require an explicit reload or copy.
class ShufflePresetEditorController extends CustomShuffleController {
  static const int maxNameLength = 80;

  final bool local;
  ShufflePreset? _basePreset;
  int? _sessionRevision;
  bool _saving = false;
  bool _conflict = false;
  String? _error;

  ShufflePresetEditorController(super.app, {ShufflePreset? preset, this.local = false})
    : _basePreset = preset,
      super(
        autosave: false,
        initialTarget: local ? CustomShuffleTarget.local : CustomShuffleTarget.server,
        initialSettings: local
            ? app.customShuffleSettings
            : CustomShuffleSettings(artistIds: preset?.artistIds ?? const [], genres: preset?.genres ?? const []),
      );

  bool get saving => _saving;

  bool get conflict => _conflict;

  String? get error => _error;

  bool get sessionValid =>
      local || (_sessionRevision == controller.connection.sessionRevision && controller.authState.isAuthorized);

  @override
  Future<void> initializeFeature() async {
    if (!local) {
      _sessionRevision = controller.connection.sessionRevision;
      listenTo(controller.shufflePresetsStream, _receivePresets);
      listenTo(controller.authStream, (_) => update(() {}));
    }

    await super.initializeFeature();
  }

  Future<bool> submit(String rawName, {bool saveCopy = false}) async {
    if (_saving || isDisposed || !sessionValid) {
      return false;
    }

    final name = rawName.trim();

    if (!local && (name.isEmpty || name.length > maxNameLength)) {
      update(() => _error = 'Enter a name of 1–$maxNameLength characters.');

      return false;
    }

    if (_conflict && !saveCopy) {
      return false;
    }

    update(() {
      _saving = true;
      _error = null;
    });

    try {
      if (local) {
        await controller.updateCustomShuffleSettings(
          localArtistIds: selectedLocalArtistIds.toList(),
          localGenres: _sortedGenres(selectedLocalGenres),
        );
      } else {
        await controller.saveShufflePreset(
          id: saveCopy ? null : _basePreset?.id,
          name: name,
          artistIds: selectedArtistIds.toList(),
          genres: _sortedGenres(selectedGenres),
          expectedRevision: saveCopy ? null : _basePreset?.revision,
        );
      }

      return !isDisposed && sessionValid;
    } catch (error) {
      if (error is ApiException && error.statusCode == 409) {
        update(() {
          _conflict = true;
          _error = 'This preset changed on another device. Your draft is preserved.';
        });
      } else {
        update(() => _error = 'Could not save. Check your connection and try again.');
      }

      return false;
    } finally {
      update(() => _saving = false);
    }
  }

  /// The UI updates its name field only when the user chooses this operation.
  Future<ShufflePreset?> reloadLatest() async {
    if (local || _saving || !sessionValid) {
      return null;
    }

    update(() => _saving = true);

    try {
      await controller.loadShufflePresets();

      if (isDisposed || !sessionValid) {
        return null;
      }

      final latest = _findPreset(controller.shufflePresets);

      if (latest == null) {
        update(() {
          _conflict = true;
          _error = 'This preset was deleted. Save a copy to keep your draft.';
        });

        return null;
      }

      _basePreset = latest;
      replaceServerSelection(artistIds: latest.artistIds, genres: latest.genres);
      update(() {
        _conflict = false;
        _error = null;
      });

      return latest;
    } catch (_) {
      update(() => _error = 'Could not reload. Your draft is preserved.');

      return null;
    } finally {
      update(() => _saving = false);
    }
  }

  void _receivePresets(List<ShufflePreset> presets) {
    if (_saving || _basePreset == null || !sessionValid) {
      return;
    }

    final latest = _findPreset(presets);

    if (latest == null || latest.revision != _basePreset!.revision) {
      update(() {
        _conflict = true;
        _error = latest == null
            ? 'This preset was deleted on another device. Your draft is preserved.'
            : 'This preset changed on another device. Your draft is preserved.';
      });
    }
  }

  ShufflePreset? _findPreset(List<ShufflePreset> presets) {
    for (final preset in presets) {
      if (preset.id == _basePreset?.id) {
        return preset;
      }
    }

    return null;
  }

  List<String> _sortedGenres(Set<String> values) {
    final sorted = values.toList();

    sorted.sort();

    return sorted;
  }
}

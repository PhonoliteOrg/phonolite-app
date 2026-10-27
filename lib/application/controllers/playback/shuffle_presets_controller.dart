import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_options.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

class ShufflePresetsController extends FeatureController {
  final AppController app;
  late final ControllerSelection<String> _selection = ControllerSelection<String>(update);
  CustomShuffleTarget _target = CustomShuffleTarget.server;
  int? _sessionRevision;
  bool _busy = false;
  String? _error;

  ShufflePresetsController(this.app);

  CustomShuffleTarget get target => _target;

  bool get selectionMode => _selection.active;

  Set<String> get selectedIds => _selection.keys();

  bool get busy => _busy;

  String? get error => _error;

  List<ShufflePreset> get selectedPresets {
    final selection = selectedIds;

    return app.shufflePresets.where((preset) => selection.contains(preset.id)).toList();
  }

  @override
  Future<void> initializeFeature() async {
    listenTo(app.authStream, _receiveAuthentication);
    listenTo(app.shufflePresetsStream, _receivePresets);

    await load();
  }

  void setTarget(CustomShuffleTarget value) {
    clearSelection();
    update(() => _target = value);
  }

  void startSelection() => _selection.clear(activate: true);

  void clearSelection() => _selection.clear();

  void toggleSelection(String id) => _selection.toggle(id);

  void selectAll() => _selection.replace(app.shufflePresets.map((preset) => preset.id));

  void deselectAll() => _selection.clear(activate: null);

  Future<void> load() async {
    if (!app.shufflePresetsAvailable) {
      update(() {});

      return;
    }

    final revision = app.connection.sessionRevision;

    if (_sessionRevision == revision) {
      return;
    }

    _sessionRevision = revision;
    await _run(app.loadShufflePresets);
  }

  Future<void> apply(ShufflePreset preset) => _run(() => app.applyShufflePreset(preset));

  Future<void> importExisting() => _run(app.importCustomShufflePreset);

  Future<void> deleteSelected(List<ShufflePreset> presets) async {
    final revision = app.connection.sessionRevision;

    await _run(() async {
      for (final preset in presets) {
        if (isDisposed || app.connection.sessionRevision != revision || !app.shufflePresetsAvailable) {
          return;
        }

        await app.deleteShufflePreset(preset);
      }

      clearSelection();
    });
  }

  void _receiveAuthentication(AuthState state) {
    clearSelection();
    unawaited(load().catchError(reportInitializationFailure));
  }

  void _receivePresets(List<ShufflePreset> presets) {
    final availableIds = presets.map((preset) => preset.id).toSet();

    _selection.replace(selectedIds.where(availableIds.contains), activate: null);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || isDisposed) {
      return;
    }

    update(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
    } catch (error) {
      update(() {
        _error = error is ApiException && error.statusCode == 409
            ? 'A preset changed on another device. Review the updated list and try again.'
            : 'Could not update custom shuffles. Check your connection and try again.';
      });
    } finally {
      update(() => _busy = false);
    }
  }
}

import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/infrastructure/platform/files/macos_directory_access.dart';

class StoragePathController extends FeatureController {
  final Future<void> Function(String?) onSave;
  final MacosDirectoryAccess _directoryAccess;
  bool _saving = false;
  bool _choosing = false;
  String? _error;

  StoragePathController(this.onSave, {this._directoryAccess = const MacosDirectoryAccess()});

  bool get saving => _saving;

  bool get busy => _saving || _choosing;

  bool get requiresDirectoryPicker => _directoryAccess.isSupported;

  String? get error => _error;

  Future<bool> save(String input) async {
    if (busy || isDisposed) {
      return false;
    }

    void beginSaving() {
      _saving = true;
      _error = null;
    }

    update(beginSaving);

    try {
      final path = input.trim();

      await onSave(path.isEmpty ? null : path);

      return !isDisposed;
    } catch (error) {
      void publishFailure() {
        _saving = false;
        _error = error.toString();
      }

      update(publishFailure);

      return false;
    }
  }

  Future<String?> chooseDirectory(String? initialPath) async {
    if (busy || isDisposed || !requiresDirectoryPicker) {
      return null;
    }

    update(() {
      _choosing = true;
      _error = null;
    });

    try {
      return await _directoryAccess.selectDirectory(initialPath);
    } catch (error) {
      update(() => _error = error.toString());

      return null;
    } finally {
      update(() => _choosing = false);
    }
  }
}

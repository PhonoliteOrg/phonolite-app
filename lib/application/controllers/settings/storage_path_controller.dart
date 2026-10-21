import 'package:phonolite_app/application/controllers/feature_controller.dart';

class StoragePathController extends FeatureController {
  final Future<void> Function(String?) onSave;
  bool _saving = false;
  String? _error;

  StoragePathController(this.onSave);

  bool get saving => _saving;

  String? get error => _error;

  Future<bool> save(String input) async {
    if (_saving || isDisposed) {
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
}

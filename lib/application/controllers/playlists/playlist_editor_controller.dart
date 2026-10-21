import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_editor_values.dart';
import 'package:phonolite_app/infrastructure/platform/files/playlist_image_file_picker.dart';

export 'package:phonolite_app/data/models/collections/playlist_editor_values.dart';

class PlaylistEditorController extends FeatureController {
  static const int maxNameLength = 32;
  static const int maxDescriptionLength = 500;
  static const int _maxImageBytes = 5 * 1024 * 1024;
  static const List<String> _imageExtensions = <String>['jpg', 'jpeg', 'png', 'webp'];

  final PlaylistEditorSubmit onSubmit;
  PlaylistEditorTarget _target;
  bool _saving = false;
  Uint8List? _selectedImageBytes;
  String? _selectedImageContentType;
  String? _imageError;

  PlaylistEditorController(this.onSubmit, this._target);

  PlaylistEditorTarget get target => _target;

  bool get saving => _saving;

  Uint8List? get selectedImageBytes => _selectedImageBytes?.asUnmodifiableView();

  String? get imageError => _imageError;

  PlaylistImageEdit get imageEdit {
    final bytes = _selectedImageBytes;
    if (bytes != null) {
      return PlaylistImageEdit.replace(
        bytes: bytes,
        contentType: _selectedImageContentType ?? 'application/octet-stream',
      );
    }

    return const PlaylistImageEdit.keep();
  }

  void setTarget(PlaylistEditorTarget value) => update(() => _target = value);

  Future<bool> submit(String name, String description) async {
    if (_saving) {
      return false;
    }

    var trimmed = name.trim();

    if (trimmed.isEmpty) {
      return false;
    }

    if (trimmed.length > maxNameLength) {
      trimmed = trimmed.substring(0, maxNameLength);
    }

    description = description.trim();

    update(() => _saving = true);

    try {
      await Future<void>.sync(() => onSubmit(trimmed, description, imageEdit, _target));

      return !isDisposed;
    } catch (err) {
      if (!isDisposed) {
        void showSaveFailure() {
          _saving = false;
          _imageError = 'Failed to save playlist.';
        }

        update(showSaveFailure);
      }
    }

    return false;
  }

  Future<void> pickImage() async {
    update(() => _imageError = null);

    final XFile? file;

    try {
      file = await openPlaylistImageFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'Images',
            extensions: _imageExtensions,
            mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
          ),
        ],
      );
    } catch (_) {
      if (isDisposed) {
        return;
      }

      update(() => _imageError = 'Image picker is unavailable.');

      return;
    }

    if (file == null) {
      return;
    }

    final Uint8List bytes;

    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (isDisposed) {
        return;
      }

      update(() => _imageError = 'Selected image could not be read.');

      return;
    }

    if (bytes.isEmpty) {
      update(() => _imageError = 'Selected image is empty.');

      return;
    }

    if (bytes.length > _maxImageBytes) {
      update(() => _imageError = 'Selected image is too large.');

      return;
    }

    final contentType = contentTypeForFile(file, bytes);

    if (contentType == 'application/octet-stream') {
      update(() => _imageError = 'Selected image type is not supported.');

      return;
    }

    void selectImage() {
      _selectedImageBytes = bytes;
      _selectedImageContentType = contentType;
    }

    update(selectImage);
  }

  String contentTypeForFile(XFile file, Uint8List bytes) {
    final mimeType = file.mimeType?.split(';').first.trim().toLowerCase();

    if (mimeType == 'image/jpeg' || mimeType == 'image/jpg' || mimeType == 'image/png' || mimeType == 'image/webp') {
      return mimeType == 'image/jpg' ? 'image/jpeg' : mimeType!;
    }

    final nameType = contentTypeForName(file.name);

    if (nameType != 'application/octet-stream') {
      return nameType;
    }

    return contentTypeForBytes(bytes);
  }

  String contentTypeForName(String name) {
    final lower = name.trim().toLowerCase();

    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }

    if (lower.endsWith('.png')) {
      return 'image/png';
    }

    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'application/octet-stream';
  }

  String contentTypeForBytes(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    return 'application/octet-stream';
  }
}

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import 'playlist_image_file_picker_stub.dart'
    if (dart.library.io) 'playlist_image_file_picker_io.dart'
    as platform;

Future<XFile?> openPlaylistImageFile({
  required List<XTypeGroup> acceptedTypeGroups,
}) async {
  if (_usePhotoLibraryPicker) {
    return image_picker.ImagePicker().pickImage(
      source: image_picker.ImageSource.gallery,
      imageQuality: 92,
    );
  }
  try {
    return await openFile(acceptedTypeGroups: acceptedTypeGroups);
  } on PlatformException catch (err) {
    final fallback = await platform.openPlaylistImageFileFallback();
    if (fallback != null) {
      return fallback;
    }
    if (_isMissingFileSelectorChannel(err)) {
      return null;
    }
    rethrow;
  }
}

bool _isMissingFileSelectorChannel(PlatformException err) {
  return err.code == 'channel-error' &&
      (err.message ?? '').contains('file_selector');
}

bool get _usePhotoLibraryPicker {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

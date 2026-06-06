import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'playlist_image_file_picker_stub.dart'
    if (dart.library.io) 'playlist_image_file_picker_io.dart'
    as platform;

Future<XFile?> openPlaylistImageFile({
  required List<XTypeGroup> acceptedTypeGroups,
}) async {
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

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

void main() {
  test('audio extensions follow the response content type', () {
    const cases = {
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/x-m4a': 'm4a',
      'AUDIO/FLAC': 'flac',
      'audio/ogg; codecs=opus': 'ogg',
      'audio/opus': 'opus',
      'audio/x-wav': 'wav',
      'application/octet-stream': 'audio',
      '': 'audio',
    };

    for (final entry in cases.entries) {
      expect(OfflineLibraryStorage.extensionFromContentType(entry.key), entry.value, reason: entry.key);
    }
    expect(OfflineLibraryStorage.extensionFromContentType(null), 'audio');
  });

  test('image extensions follow the response content type', () {
    const cases = {
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png; charset=binary': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
      'image/avif': 'img',
    };

    for (final entry in cases.entries) {
      expect(OfflineLibraryStorage.extensionFromImageContentType(entry.key), entry.value, reason: entry.key);
    }
    expect(OfflineLibraryStorage.extensionFromImageContentType(null), 'img');
  });

  test('a content disposition filename supplies a lowercase safe extension', () {
    const cases = <String?, String?>{
      'attachment; filename="Track One.FLAC"': 'flac',
      "attachment; filename*=UTF-8''Track%20One.opus": 'opus',
      'attachment; filename=track.mp3; size=10': 'mp3',
      'attachment; filename="no-extension"': null,
      'attachment': null,
      '': null,
      null: null,
    };

    for (final entry in cases.entries) {
      expect(OfflineLibraryStorage.extensionFromContentDisposition(entry.key), entry.value, reason: '${entry.key}');
    }
  });
}

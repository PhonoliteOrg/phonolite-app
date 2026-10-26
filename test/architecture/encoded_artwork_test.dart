import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/rules/artwork/encoded_artwork.dart';

const _start = [0xff, 0xd8];
const _end = [0xff, 0xd9];
const _frame = [0xff, 0xc0, 0x00, 0x0b, 8, 0, 1, 0, 1, 1, 1, 0x11, 0];
const _scan = [0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 63, 0];

Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);

// A generated white 1x1 baseline JPEG, independent of the user's artwork.
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/'
  '2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/'
  '8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2Jy'
  'ggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5'
  'usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQA'
  'AQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3'
  'eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9'
  'U6KKKAP/2Q==',
);

void main() {
  test('accepts complete baseline JPEG and trailing padding or metadata', () {
    expect(hasCompleteArtworkBytes(_jpeg), isTrue);
    expect(hasCompleteArtworkBytes(_bytes([..._jpeg, 0, 0, 0xff, 0xe1, 0, 8])), isTrue);
  });

  test('rejects every incomplete prefix of a complete JPEG', () {
    for (var length = 2; length < _jpeg.length; length++) {
      expect(
        hasCompleteArtworkBytes(Uint8List.sublistView(_jpeg, 0, length)),
        isFalse,
        reason: 'truncated at byte $length',
      );
    }
  });

  test('rejects a 128 KiB partial JPEG even when its scan data remains usable', () {
    final partial = _bytes([..._start, ..._frame, ..._scan, ...List.filled(128 * 1024, 0x55)]);
    expect(hasCompleteArtworkBytes(Uint8List.sublistView(partial, 0, 128 * 1024)), isFalse);
  });

  test('accepts progressive scans separated by tables and more scan headers', () {
    final progressiveFrame = [..._frame]..[1] = 0xc2;
    expect(
      hasCompleteArtworkBytes(
        _bytes([..._start, ...progressiveFrame, ..._scan, 1, 2, 3, 0xff, 0xc4, 0, 4, 0, 0, ..._scan, 4, 5, 6, ..._end]),
      ),
      isTrue,
    );
  });

  test('does not mistake an EOI in APP or comment payloads for the image end', () {
    for (final marker in [0xe0, 0xe1, 0xe2, 0xed, 0xfe]) {
      final prefix = [..._start, 0xff, marker, 0, 6, 1, ..._end, 2, ..._frame, ..._scan, 3];
      expect(hasCompleteArtworkBytes(_bytes(prefix)), isFalse);
      expect(hasCompleteArtworkBytes(_bytes([...prefix, ..._end])), isTrue);
    }
    // Even an EOI at EOF belongs to the declared segment, not the image.
    expect(hasCompleteArtworkBytes(_bytes([..._start, 0xff, 0xe1, 0, 4, ..._end])), isFalse);
  });

  test('handles entropy stuffing, restart markers, TEM, and marker fill bytes', () {
    final prefix = [..._start, 0xff, 0x01, ..._frame, ..._scan, 1, 0xff, 0, 0xd9, 2];
    for (var marker = 0xd0; marker <= 0xd7; marker++) {
      prefix.addAll([0xff, marker, 3]);
    }
    prefix.addAll([0xff, 0x01, 4]);
    expect(hasCompleteArtworkBytes(_bytes(prefix)), isFalse);
    expect(hasCompleteArtworkBytes(_bytes([...prefix, 0xff, ..._end])), isTrue);
  });

  test('continues entropy data after a DNL segment', () {
    final prefix = [..._start, ..._frame, ..._scan, 1, 0xff, 0xdc, 0, 4, 0, 1, 2, 3];
    expect(hasCompleteArtworkBytes(_bytes(prefix)), isFalse);
    expect(hasCompleteArtworkBytes(_bytes([...prefix, ..._end])), isTrue);
  });

  test('rejects malformed segment sizes, dangling markers, and missing scans without throwing', () {
    for (final malformed in <List<int>>[
      _start,
      [..._start, ..._end],
      [..._start, ..._frame, ..._end],
      [..._start, 0xff],
      [..._start, 0xff, 0xff],
      [..._start, 0xff, 0x00, ..._end],
      [..._start, 0xff, 0xe1],
      [..._start, 0xff, 0xe1, 0],
      [..._start, 0xff, 0xe1, 0, 0, ..._end],
      [..._start, 0xff, 0xe1, 0, 1, ..._end],
      [..._start, 0xff, 0xe1, 0xff, 0xff, ..._end],
      [..._start, ..._frame, ..._scan, 0xff],
      [..._start, ..._frame, ..._scan, 0xff, 0x00],
      [..._start, ..._frame, ..._scan, ..._start, ..._end],
    ]) {
      expect(hasCompleteArtworkBytes(_bytes(malformed)), isFalse);
    }
  });

  test('leaves nonempty PNG GIF WebP and other format validation to the decoder', () {
    expect(hasCompleteArtworkBytes(Uint8List(0)), isFalse);
    for (final signature in [
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      ascii.encode('GIF89a'),
      ascii.encode('RIFF\x00\x00\x00\x00WEBP'),
      [1, 2, 3],
    ]) {
      expect(hasCompleteArtworkBytes(_bytes(signature)), isTrue);
    }
  });
}

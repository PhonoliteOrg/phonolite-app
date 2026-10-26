import 'dart:typed_data';

/// Rejects empty artwork and structurally incomplete JPEG codestreams.
///
/// JPEG decoders can display partial scans even when a transfer lost its tail.
/// Walk markers to find the real end of image rather than mistaking bytes in
/// metadata for it. Baseline/progressive scans, stuffed bytes, restart markers,
/// and bytes following the end marker are supported. This does not decode or
/// fully validate an image; other nonempty formats retain their existing
/// behavior, and frame decoding remains responsible for image validity.
bool hasCompleteArtworkBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    return false;
  }

  if (bytes.length < 2 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return true;
  }

  var offset = 2;
  var inScan = false;
  var sawScan = false;

  while (offset < bytes.length) {
    if (inScan) {
      while (offset < bytes.length && bytes[offset] != 0xff) {
        offset++;
      }
    }

    if (offset >= bytes.length || bytes[offset++] != 0xff) {
      return false;
    }

    // Multiple FF bytes can fill the space before a marker.
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }

    if (offset >= bytes.length) {
      return false;
    }

    final marker = bytes[offset++];

    if (marker == 0x00) {
      if (!inScan) {
        return false;
      }

      // FF00 represents an entropy-coded FF byte, never a marker.
      continue;
    }

    if (marker == 0xd9) {
      return sawScan;
    }

    if (marker == 0xd8) {
      return false;
    }

    // TEM and restart markers have no length or payload.
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }

    if (offset + 2 > bytes.length) {
      return false;
    }

    final length = (bytes[offset] << 8) | bytes[offset + 1];

    // Segment lengths include their own two bytes, but not the marker.
    if (length < 2 || length > bytes.length - offset) {
      return false;
    }

    offset += length;

    if (marker == 0xda) {
      sawScan = true;
      inScan = true;
    } else if (marker != 0xdc) {
      // DNL can occur within an entropy-coded scan. Other segments end it;
      // progressive images can then declare tables and start another scan.
      inScan = false;
    }
  }

  return false;
}

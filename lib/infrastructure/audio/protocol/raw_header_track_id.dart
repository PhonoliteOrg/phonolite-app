import 'dart:convert';
import 'dart:typed_data';

const List<int> _rawHeaderMagic = [79, 80, 85, 83, 82, 48, 49, 0];

const int _rawHeaderMinLen = 40;

bool hasRawHeaderMagic(Uint8List prefix) {
  if (prefix.length < _rawHeaderMagic.length) {
    return false;
  }

  for (var i = 0; i < _rawHeaderMagic.length; i++) {
    if (prefix[i] != _rawHeaderMagic[i]) {
      return false;
    }
  }

  return true;
}

String? extractRawHeaderTrackId(Uint8List headerBytes) {
  if (headerBytes.length < 12) {
    return null;
  }

  if (!hasRawHeaderMagic(headerBytes)) {
    return null;
  }

  if (headerBytes[8] != 1) {
    return null;
  }

  final headerLen = headerBytes[10] | (headerBytes[11] << 8);

  if (headerLen < _rawHeaderMinLen) {
    return null;
  }

  if (headerBytes.length < headerLen) {
    return null;
  }

  var idx = 12;

  if (idx + 4 + 1 + 1 + 4 + 4 + 2 + 2 * 6 > headerLen) {
    return null;
  }

  idx += 4; // sampleRate
  idx += 1; // channels
  idx += 1; // frameMs
  idx += 4; // bitrate
  idx += 4; // duration
  idx += 2; // preSkip

  final trackIdLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final titleLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final artistLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final albumLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final codecLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final containerLen = headerBytes[idx] | (headerBytes[idx + 1] << 8);
  idx += 2;

  final totalLen = trackIdLen + titleLen + artistLen + albumLen + codecLen + containerLen;

  if (idx + totalLen > headerLen) {
    return null;
  }

  if (trackIdLen == 0) {
    return null;
  }

  final end = idx + trackIdLen;

  if (end > headerBytes.length) {
    return null;
  }

  return utf8.decode(headerBytes.sublist(idx, end), allowMalformed: true);
}

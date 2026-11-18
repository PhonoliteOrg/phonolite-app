import 'dart:typed_data';

enum PlaylistImageEditKind { keep, clear, replace }

class PlaylistImageEdit {
  final PlaylistImageEditKind kind;
  final Uint8List? bytes;
  final String? contentType;

  const PlaylistImageEdit.keep() : kind = PlaylistImageEditKind.keep, bytes = null, contentType = null;

  const PlaylistImageEdit.clear() : kind = PlaylistImageEditKind.clear, bytes = null, contentType = null;

  const PlaylistImageEdit.replace({required this.bytes, required this.contentType})
    : kind = PlaylistImageEditKind.replace;
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/server/transport/streamed_response_body.dart';

/// Loads PNG artwork for the native now-playing surface.
///
/// Failures are optional artwork misses; playback does not depend on images.
/// Remote requests borrow the session transport. The caller tracks the selected track.
class NowPlayingArtworkLoader {
  final ServerConnection? connection;
  final Future<Uint8List?> Function(Uint8List) _decode;

  NowPlayingArtworkLoader({this.connection, Future<Uint8List?> Function(Uint8List)? decode})
    : _decode = decode ?? _decodePng;

  Future<Uint8List?> loadRemote(String url, {required int sessionRevision}) async {
    final server = connection;
    if (server == null || server.sessionRevision != sessionRevision) return null;
    try {
      final response = await server.openArtwork(url);
      if (server.sessionRevision != sessionRevision || response.statusCode < 200 || response.statusCode >= 300) {
        await discardResponseBody(response);
        return null;
      }
      final bytes = await readBoundedBody(
        response.stream,
        deadline: const Duration(seconds: 15),
        maximumBytes: 16 * 1024 * 1024,
        tooLarge: (_) => const HttpException('Artwork exceeds encoded byte limit'),
      );
      if (server.sessionRevision != sessionRevision) return null;
      final decoded = await _decode(bytes);
      return server.sessionRevision == sessionRevision ? decoded : null;
    } on Object catch (_) {
      // Artwork is optional (see class docs); a miss leaves the now-playing surface without an image.
      return null;
    }
  }

  Future<Uint8List?> loadFile(String path) async {
    try {
      return await _decode(await File(path).readAsBytes());
    } on Object catch (_) {
      // Artwork is optional (see class docs); a miss leaves the now-playing surface without an image.
      return null;
    }
  }

  static const int _maxArtworkDimension = 1024;

  static ui.TargetImageSize _fitWithinLimit(int width, int height) {
    final longest = width > height ? width : height;

    if (longest <= _maxArtworkDimension) {
      return ui.TargetImageSize(width: width, height: height);
    }

    final scale = _maxArtworkDimension / longest;

    return ui.TargetImageSize(width: (width * scale).round(), height: (height * scale).round());
  }

  static Future<Uint8List?> _decodePng(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }

    // Fit within the limit keeping aspect ratio and never upscale; passing both targetWidth and
    // targetHeight would force exactly 1024x1024, stretching non-square art and inflating small art.
    // instantiateImageCodecWithSize takes ownership of the buffer and disposes it.
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: _fitWithinLimit,
    );

    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;

      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);

        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import '../entities/server_trust.dart';

/// Loads PNG artwork for the native now-playing surface.
///
/// Failures are optional artwork misses; playback does not depend on images.
/// The caller owns an injected HTTP client and decides whether a completed
/// request still belongs to the current track/session.
class NowPlayingArtworkLoader {
  NowPlayingArtworkLoader({
    http.Client? client,
    Future<Uint8List?> Function(Uint8List)? decode,
  }) : _get = client?.get ?? _pinnedGet,
       _decode = decode ?? _decodePng;

  final Future<http.Response> Function(Uri, {Map<String, String>? headers})
  _get;
  final Future<Uint8List?> Function(Uint8List) _decode;

  static Future<http.Response> _pinnedGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final client = pinnedApiClient(() => uri.toString());
    try {
      return await client.get(uri, headers: headers);
    } finally {
      client.close();
    }
  }

  Future<Uint8List?> loadRemote(String url, {required String token}) async {
    try {
      final response = await _get(
        Uri.parse(url),
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return await _decode(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> loadFile(String path) async {
    try {
      return await _decode(await File(path).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _decodePng(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1024,
      targetHeight: 1024,
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

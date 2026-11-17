import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Shared HTTP success and JSON-shape rules for buffered API responses.
/// Endpoint clients supply model factories; streaming and binary endpoints
/// retain their own payload contracts.
class ApiResponseDecoder {
  const ApiResponseDecoder();

  void requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body, retryAfter: retryAfter(response));
    }
  }

  Duration? retryAfter(http.BaseResponse response, {DateTime? now}) {
    final header = response.headers['retry-after'];

    if (header == null) {
      return null;
    }

    final seconds = int.tryParse(header.trim());

    if (seconds != null) {
      return Duration(seconds: seconds < 0 ? 0 : seconds);
    }

    try {
      final delay = HttpDate.parse(header).difference(now ?? DateTime.now());

      return delay.isNegative ? Duration.zero : delay;
    } on HttpException {
      return null;
    }
  }

  Future<Map<String, dynamic>> object(http.Response response) async {
    requireSuccess(response);

    if (response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = await _decode(response.bodyBytes);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Unexpected response payload');
  }

  Future<List<Map<String, dynamic>>> list(http.Response response, {required String path}) async {
    requireSuccess(response);

    final decoded = await _decode(response.bodyBytes);

    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }

    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }

    throw Exception('Expected list response for $path');
  }

  static final Converter<List<int>, Object?> _jsonFromUtf8 = utf8.decoder.fuse(json.decoder);

  /// Decodes API JSON (UTF-8 by the JSON spec) straight from bytes. `http.Response.body` would
  /// re-decode the whole body on every read; large bodies are decoded entirely off the UI isolate.
  Future<dynamic> _decode(Uint8List bytes) async => bytes.length >= 64 * 1024
      ? await Isolate.run<dynamic>(() => _jsonFromUtf8.convert(bytes))
      : _jsonFromUtf8.convert(bytes);
}

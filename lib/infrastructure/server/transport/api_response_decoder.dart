import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Shared HTTP success and JSON-shape rules for buffered API responses.
/// Endpoint clients supply model factories; streaming and binary endpoints
/// retain their own payload contracts.
class ApiResponseDecoder {
  const ApiResponseDecoder();

  void requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> object(http.Response response) async {
    requireSuccess(response);

    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = await _decode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Unexpected response payload');
  }

  Future<List<Map<String, dynamic>>> list(http.Response response, {required String path}) async {
    requireSuccess(response);

    final decoded = await _decode(response.body);

    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }

    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }

    throw Exception('Expected list response for $path');
  }

  Future<dynamic> _decode(String body) async =>
      body.length >= 64 * 1024 ? await Isolate.run<dynamic>(() => jsonDecode(body)) : jsonDecode(body);
}

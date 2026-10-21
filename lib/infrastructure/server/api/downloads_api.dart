import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/models/server/track_download_stream.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class DownloadsApi extends JsonApiEndpoint {
  final String Function(String trackId) _trackDownloadUrl;

  DownloadsApi(super.transport, {required String Function(String trackId) trackDownloadUrl})
    : _trackDownloadUrl = trackDownloadUrl;

  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    final payload = <String, dynamic>{
      'track_ids': trackIds,
      if (clientBatchId != null && clientBatchId.trim().isNotEmpty) 'client_batch_id': clientBatchId.trim(),
    };

    return postValue('/download/batches', payload, DownloadBatchManifest.fromJson);
  }

  Future<ServerCapabilities> fetchCapabilities() async {
    return getValue(
      '/server/capabilities',
      ServerCapabilities.fromJson,
      timeout: ApiTransport.healthRequestTimeout,
      retryable: false,
    );
  }

  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) async {
    return postValue('/download/v2/jobs', {
      'client_id': clientId,
      'client_request_id': clientRequestId,
      'scope': scope.toJson(),
    }, DownloadJobV2.fromJson);
  }

  Future<List<DownloadJobV2>> fetchDownloadJobs({String? clientId, String? scopeKind, String? scopeId}) async {
    final query = <String, String>{
      if (clientId != null && clientId.trim().isNotEmpty) 'client_id': clientId.trim(),
      if (scopeKind != null && scopeKind.trim().isNotEmpty) 'scope_kind': scopeKind.trim(),
      if (scopeId != null && scopeId.trim().isNotEmpty) 'scope_id': scopeId.trim(),
    };
    final suffix = query.isEmpty
        ? ''
        : '?${query.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';

    return getValues('/download/v2/jobs$suffix', DownloadJobV2.fromJson);
  }

  Future<void> applyDownloadJobAction({required String jobId, required String action}) async {
    final encoded = ApiTransport.encodePathSegment(jobId);

    await transport.postVoid('/download/v2/jobs/$encoded/actions', {'action': action});
  }

  String buildTrackDownloadUrl(String trackId) {
    final encoded = ApiTransport.encodePathSegment(trackId);

    return '${transport.baseUrl}/download/tracks/$encoded';
  }

  String buildDownloadUrl(String trackId, {String? downloadUrl}) {
    final value = downloadUrl?.trim();

    if (value == null || value.isEmpty) {
      return _trackDownloadUrl(trackId);
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('/api/')) {
      final root = transport.ensureRoot(transport.baseUrl);

      return '${root.endsWith('/') ? root.substring(0, root.length - 1) : root}$value';
    }

    if (value.startsWith('/')) {
      return '${transport.baseUrl}$value';
    }

    return '${transport.baseUrl}/$value';
  }

  Future<TrackDownloadStream> openTrackDownload(
    String trackId, {
    int? startByte,
    String? ifRange,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) async {
    final request = http.Request('GET', Uri.parse(_trackDownloadUrl(trackId)));
    request.headers.addAll(transport.buildHeaders());

    if (startByte != null && startByte > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$startByte-';

      if (ifRange != null && ifRange.trim().isNotEmpty) {
        request.headers[HttpHeaders.ifRangeHeader] = ifRange.trim();
      }
    }

    final response = await transport.client.send(request).timeout(timeout);

    if (response.statusCode != 200 && response.statusCode != 206) {
      final body = await response.stream.bytesToString();

      throw ApiException(response.statusCode, body);
    }

    return TrackDownloadStream(
      statusCode: response.statusCode,
      stream: response.stream,
      contentLength: response.contentLength == null || response.contentLength! < 0 ? null : response.contentLength,
      contentRange: response.headers[HttpHeaders.contentRangeHeader],
      contentType: response.headers[HttpHeaders.contentTypeHeader],
      contentDisposition: response.headers['content-disposition'],
      etag: response.headers[HttpHeaders.etagHeader],
      sha256: response.headers['x-phonolite-sha256'],
    );
  }
}

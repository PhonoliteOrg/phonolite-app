import 'dart:async';

class TrackDownloadStream {
  final int statusCode;
  final Stream<List<int>> stream;
  final int? contentLength;
  final String? contentRange;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;

  TrackDownloadStream({
    required this.statusCode,
    required this.stream,
    this.contentLength,
    this.contentRange,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });
}

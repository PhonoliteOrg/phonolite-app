import 'dart:isolate';

import 'package:phonolite_app/data/models/auth/server_trust.dart';

enum DownloadWorkerFailureKind { canceled, corrupt, error }

class DownloadWorkerStart {
  final DownloadWorkerRequest request;
  final SendPort sendPort;

  const DownloadWorkerStart(this.request, this.sendPort);
}

class DownloadWorkerRequest {
  final String serverBaseUrl;
  final String trackId;
  final String url;
  final String token;
  final ServerTrust? trust;
  final String partialPath;
  final int? startByte;
  final String? ifRange;
  final int? expectedBytes;
  final String? expectedSha256;
  final int progressIntervalMs;
  final int diskFlushBytes;
  final int timeoutSeconds;

  const DownloadWorkerRequest({
    required this.serverBaseUrl,
    required this.trackId,
    required this.url,
    required this.token,
    required this.trust,
    required this.partialPath,
    required this.progressIntervalMs,
    required this.diskFlushBytes,
    required this.timeoutSeconds,
    this.startByte,
    this.ifRange,
    this.expectedBytes,
    this.expectedSha256,
  });
}

class DownloadWorkerReady {
  final SendPort cancelPort;

  const DownloadWorkerReady(this.cancelPort);
}

class DownloadWorkerMetadata {
  final int bytesDownloaded;
  final int? bytesTotal;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;

  const DownloadWorkerMetadata({
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });
}

class DownloadWorkerProgress {
  final int bytesDownloaded;
  final int? bytesTotal;

  const DownloadWorkerProgress({required this.bytesDownloaded, required this.bytesTotal});
}

class DownloadWorkerComplete {
  final int bytesDownloaded;
  final int bytesTotal;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;

  const DownloadWorkerComplete({
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });
}

class DownloadWorkerFailure {
  final int? statusCode;
  final DownloadWorkerFailureKind kind;
  final String message;

  const DownloadWorkerFailure({required this.kind, required this.message, this.statusCode});
}

class DownloadWorkerHttpError implements Exception {
  final int statusCode;
  final String message;

  const DownloadWorkerHttpError(this.statusCode, this.message);
}

class DownloadWorkerCanceled implements Exception {
  const DownloadWorkerCanceled();
}

class DownloadWorkerCorrupt implements Exception {
  final String message;

  const DownloadWorkerCorrupt(this.message);
}

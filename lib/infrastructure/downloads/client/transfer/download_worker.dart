part of '../offline_download_client.dart';

Future<void> _downloadWorkerMain(DownloadWorkerStart start) async {
  final request = start.request;
  final cancelPort = ReceivePort();
  var canceled = false;
  var bytesDownloaded = request.startByte ?? 0;
  HttpClient? client;
  IOSink? sink;

  void cancelDownload(Object? _) {
    canceled = true;
    client?.close(force: true);
  }

  cancelPort.listen(cancelDownload);

  start.sendPort.send(DownloadWorkerReady(cancelPort.sendPort));

  try {
    void throwIfCanceled() {
      if (canceled) {
        throw const DownloadWorkerCanceled();
      }
    }

    final timeout = Duration(seconds: request.timeoutSeconds);

    if (request.trust == null) {
      throw StateError('Download server is not authenticated');
    }

    ServerTrustRegistry.register(request.serverBaseUrl, request.trust!);
    installServerTrustOverrides();

    if (ServerTrustRegistry.origin(Uri.parse(request.url)) !=
        ServerTrustRegistry.origin(Uri.parse(request.serverBaseUrl))) {
      throw StateError('Cross-server download blocked');
    }

    final partialFile = File(request.partialPath);
    final expectedBytes = request.expectedBytes;

    if (expectedBytes != null && expectedBytes > 0 && bytesDownloaded == expectedBytes) {
      // A crash may occur after the final bytes are flushed but before the
      // file is promoted. Validate it instead of requesting bytes past EOF.
      final expectedSha256 = request.expectedSha256?.trim().toLowerCase();

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final digest = await hashDownloadFile(request.partialPath);

        if (digest != expectedSha256) {
          await deleteDownloadWorkerFile(request.partialPath);

          throw const DownloadWorkerCorrupt('checksum mismatch');
        }
      }

      throwIfCanceled();

      start.sendPort.send(
        DownloadWorkerComplete(
          bytesDownloaded: bytesDownloaded,
          bytesTotal: expectedBytes,
          etag: request.ifRange,
          sha256: expectedSha256,
        ),
      );

      return;
    }

    client = HttpClient();
    throwIfCanceled();

    final httpRequest = await client.getUrl(Uri.parse(request.url)).timeout(timeout);

    httpRequest.followRedirects = false;
    httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${request.token}');
    final startByte = request.startByte;

    if (startByte != null && startByte > 0) {
      httpRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=$startByte-');
      final ifRange = request.ifRange;

      if (ifRange != null && ifRange.trim().isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.ifRangeHeader, ifRange.trim());
      }
    }

    throwIfCanceled();

    final response = await httpRequest.close().timeout(timeout);

    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      final body = await response.transform(utf8.decoder).join();

      throw DownloadWorkerHttpError(response.statusCode, 'ApiException(${response.statusCode}): $body');
    }

    if (response.statusCode == HttpStatus.ok && bytesDownloaded > 0) {
      await partialFile.writeAsBytes(const <int>[]);
      bytesDownloaded = 0;
    }

    final contentLength = response.contentLength < 0 ? null : response.contentLength;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    final bytesTotal =
        request.expectedBytes ??
        resolveDownloadBytesTotal(
          contentRange: contentRange,
          contentLength: contentLength,
          statusCode: response.statusCode,
          startByte: bytesDownloaded,
        );
    final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
    final contentDisposition = response.headers.value('content-disposition');
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final sha256Header = response.headers.value('x-phonolite-sha256');

    start.sendPort.send(
      DownloadWorkerMetadata(
        bytesDownloaded: bytesDownloaded,
        bytesTotal: bytesTotal,
        contentType: contentType,
        contentDisposition: contentDisposition,
        etag: etag,
        sha256: sha256Header,
      ),
    );

    sink = partialFile.openWrite(
      mode: response.statusCode == HttpStatus.partialContent && bytesDownloaded > 0 ? FileMode.append : FileMode.write,
    );

    final progressClock = Stopwatch();

    progressClock.start();
    final progressThrottle = DownloadProgressThrottle(
      interval: Duration(milliseconds: request.progressIntervalMs),
      initialBytes: bytesDownloaded,
    );
    var bytesSinceFlush = 0;

    await for (final chunk in response) {
      throwIfCanceled();

      sink.add(chunk);
      bytesDownloaded += chunk.length;
      bytesSinceFlush += chunk.length;

      if (bytesTotal != null && bytesDownloaded > bytesTotal) {
        throw const DownloadWorkerCorrupt('downloaded more bytes than expected');
      }

      if (bytesSinceFlush >= request.diskFlushBytes) {
        bytesSinceFlush = 0;
        await sink.flush();
      }

      // Report actual received bytes at a bounded rate, even for small files
      // and slow transfers. Disk flushing has its own independent threshold.
      if (progressThrottle.shouldReport(receivedBytes: bytesDownloaded, elapsed: progressClock.elapsed)) {
        start.sendPort.send(DownloadWorkerProgress(bytesDownloaded: bytesDownloaded, bytesTotal: bytesTotal));
      }
    }

    await sink.flush();
    await sink.close();
    sink = null;

    throwIfCanceled();

    final expectedTotal = bytesTotal ?? bytesDownloaded;

    if (expectedTotal > 0 && bytesDownloaded != expectedTotal) {
      throw DownloadWorkerCorrupt('downloaded $bytesDownloaded bytes, expected $expectedTotal');
    }

    if (progressThrottle.shouldReport(receivedBytes: bytesDownloaded, elapsed: progressClock.elapsed, force: true)) {
      start.sendPort.send(DownloadWorkerProgress(bytesDownloaded: bytesDownloaded, bytesTotal: expectedTotal));
    }

    final expectedSha256 = request.expectedSha256?.trim().toLowerCase();
    final actualSha256 = sha256Header?.trim().toLowerCase();

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await hashDownloadFile(request.partialPath);

      if (digest != expectedSha256) {
        await deleteDownloadWorkerFile(request.partialPath);

        throw const DownloadWorkerCorrupt('checksum mismatch');
      }
    }

    start.sendPort.send(
      DownloadWorkerComplete(
        bytesDownloaded: bytesDownloaded,
        bytesTotal: expectedTotal,
        contentType: contentType,
        contentDisposition: contentDisposition,
        etag: etag,
        sha256: actualSha256 ?? sha256Header,
      ),
    );
  } on DownloadWorkerHttpError catch (error) {
    start.sendPort.send(
      DownloadWorkerFailure(
        kind: DownloadWorkerFailureKind.error,
        message: error.message,
        statusCode: error.statusCode,
      ),
    );
  } on DownloadWorkerCanceled {
    start.sendPort.send(
      const DownloadWorkerFailure(kind: DownloadWorkerFailureKind.canceled, message: 'download canceled'),
    );
  } on DownloadWorkerCorrupt catch (err) {
    start.sendPort.send(DownloadWorkerFailure(kind: DownloadWorkerFailureKind.corrupt, message: err.message));
  } catch (err) {
    start.sendPort.send(
      DownloadWorkerFailure(
        kind: canceled ? DownloadWorkerFailureKind.canceled : DownloadWorkerFailureKind.error,
        message: err.toString(),
      ),
    );
  } finally {
    try {
      await sink?.close();
    } catch (_) {}

    client?.close(force: true);
    cancelPort.close();
  }
}

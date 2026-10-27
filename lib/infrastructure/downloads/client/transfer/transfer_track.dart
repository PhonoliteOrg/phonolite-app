part of '../offline_download_client.dart';

class _TrackDownloadTransfer {
  final _OfflineDownloadActorCore _host;
  final Set<String> _cancelRequested = <String>{};

  _TrackDownloadTransfer(this._host);

  Future<void> _runDownload(OfflineTrackDownload queued) async {
    var download = _host.find(queued.serverBaseUrl, _host._serverTrackId(queued)) ?? queued;

    if (download.status == OfflineDownloadStatus.paused || _host._queuedDownloadBlockedByPausedJob(download)) {
      return;
    }

    download = download.copyWith(status: OfflineDownloadStatus.preparing, updatedAt: DateTime.now(), error: null);

    if (!await _host._replace(download, persist: false)) {
      return;
    }

    File? partialFile;
    var bytesDownloaded = 0;

    try {
      if (_host.connection.baseUrl != download.serverBaseUrl ||
          _host.connection.token == null ||
          _host.connection.token!.isEmpty) {
        throw const DownloadPaused('server disconnected');
      }

      partialFile = await _host._storage.partialTrackFile(
        serverBaseUrl: download.serverBaseUrl,
        trackId: _host._serverTrackId(download),
      );

      if (await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }

      final expectedBytes = download.bytesTotal;

      if (expectedBytes != null && expectedBytes > 0 && bytesDownloaded > expectedBytes) {
        throw DownloadCorrupt('partial file is larger than expected size');
      }

      download = download.copyWith(
        status: OfflineDownloadStatus.downloading,
        updatedAt: DateTime.now(),
        partialPath: partialFile.path,
        bytesDownloaded: bytesDownloaded,
        error: null,
      );

      if (!await _host._replace(download, persist: false)) {
        return;
      }

      final key = _host._downloadKey(download);

      Future<void> applyProgress(DownloadWorkerProgress progress) async {
        if (_cancelRequested.contains(key) || _host._removedDownloadKeys.contains(key)) {
          return;
        }

        bytesDownloaded = progress.bytesDownloaded;
        download = download.copyWith(
          updatedAt: DateTime.now(),
          bytesDownloaded: progress.bytesDownloaded,
          bytesTotal: progress.bytesTotal,
        );

        await _host._replace(download, persist: false);
      }

      Future<void> applyMetadata(DownloadWorkerMetadata metadata) async {
        if (_cancelRequested.contains(key) || _host._removedDownloadKeys.contains(key)) {
          return;
        }

        bytesDownloaded = metadata.bytesDownloaded;
        download = download.copyWith(
          updatedAt: DateTime.now(),
          partialPath: partialFile!.path,
          bytesDownloaded: metadata.bytesDownloaded,
          bytesTotal: metadata.bytesTotal,
          etag: metadata.etag ?? download.etag,
          expectedSha256: metadata.sha256 ?? download.expectedSha256,
          contentType: metadata.contentType ?? download.contentType,
          error: null,
        );

        await _host._replace(download, persist: true);
      }

      final workerResult = await _downloadOnWorker(
        key: key,
        request: DownloadWorkerRequest(
          serverBaseUrl: download.serverBaseUrl,
          trackId: _host._serverTrackId(download),
          url: download.downloadUrl?.trim().isEmpty ?? true
              ? _host.connection.buildTrackDownloadUrl(_host._serverTrackId(download))
              : _host.connection.buildDownloadUrl(_host._serverTrackId(download), downloadUrl: download.downloadUrl),
          token: _host.connection.token!,
          trust: _host.connection.trust,
          partialPath: partialFile.path,
          startByte: bytesDownloaded > 0 ? bytesDownloaded : null,
          ifRange: bytesDownloaded > 0 ? download.etag : null,
          expectedBytes: download.bytesTotal,
          expectedSha256: download.expectedSha256,
          progressIntervalMs: _OfflineDownloadActorCore._progressEmitInterval.inMilliseconds,
          diskFlushBytes: _OfflineDownloadActorCore._diskFlushBytes,
          timeoutSeconds: 30,
        ),
        onMetadata: applyMetadata,
        onProgress: applyProgress,
      );

      if (_host._disposed) {
        return;
      }

      _throwIfStopped(download);

      download = download.copyWith(
        status: OfflineDownloadStatus.validating,
        updatedAt: DateTime.now(),
        bytesDownloaded: workerResult.bytesDownloaded,
        bytesTotal: workerResult.bytesTotal,
        etag: workerResult.etag ?? download.etag,
        expectedSha256: workerResult.sha256 ?? download.expectedSha256,
        contentType: workerResult.contentType ?? download.contentType,
      );

      if (!await _host._replace(download, persist: true)) {
        return;
      }

      final extension =
          OfflineLibraryStorage.extensionFromContentDisposition(workerResult.contentDisposition) ??
          OfflineLibraryStorage.extensionFromContentType(workerResult.contentType ?? download.contentType);
      final finalFile = await _host._storage.trackFile(
        serverBaseUrl: download.serverBaseUrl,
        trackId: _host._serverTrackId(download),
        extension: extension,
      );

      developer.Timeline.startSync('offline.download.promote');
      late final File promoted;

      try {
        if (await finalFile.exists()) {
          await finalFile.delete();
        }

        promoted = await _promotePartial(partialFile, finalFile);
      } finally {
        developer.Timeline.finishSync();
      }

      final completed = download.copyWith(
        status: OfflineDownloadStatus.downloaded,
        updatedAt: DateTime.now(),
        filePath: promoted.path,
        partialPath: null,
        bytesDownloaded: workerResult.bytesDownloaded,
        bytesTotal: workerResult.bytesTotal,
        error: null,
      );

      if (!await _host._replace(completed, persist: true)) {
        return;
      }

      _host._scheduleLocalUserDataReload();
      _host._queueArtworkHydration(completed);

      AppLogger.status('Downloaded ${download.track.title}');
    } on DownloadPaused catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }

      final latest = _host.find(download.serverBaseUrl, _host._serverTrackId(download));

      if (latest == null ||
          (latest.status != OfflineDownloadStatus.paused && !_host._activeDownloadStatus(latest.status))) {
        return;
      }

      await _host._replace(
        download.copyWith(
          status: OfflineDownloadStatus.paused,
          updatedAt: DateTime.now(),
          partialPath: partialFile?.path,
          bytesDownloaded: bytesDownloaded,
          error: err.message,
        ),
        persist: true,
      );
    } on DownloadCanceled {
      await _host._deleteIfExists(partialFile?.path);

      await _host._replace(
        download.copyWith(
          status: OfflineDownloadStatus.canceled,
          updatedAt: DateTime.now(),
          partialPath: null,
          bytesDownloaded: 0,
          error: null,
        ),
        persist: true,
      );
    } on DownloadCorrupt catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }

      if (!await _host._replace(
        download.copyWith(
          status: OfflineDownloadStatus.corrupt,
          updatedAt: DateTime.now(),
          partialPath: partialFile?.path,
          bytesDownloaded: bytesDownloaded,
          error: err.message,
        ),
        persist: true,
      )) {
        return;
      }

      AppLogger.warning('Download corrupt for ${download.track.title}: $err');
    } catch (err) {
      if (partialFile != null && await partialFile.exists()) {
        bytesDownloaded = await partialFile.length();
      }

      final shouldPause =
          _host.connection.baseUrl != download.serverBaseUrl ||
          _host.connection.token == null ||
          _host.connection.token!.isEmpty;
      final failed = download.copyWith(
        status: shouldPause ? OfflineDownloadStatus.paused : OfflineDownloadStatus.failed,
        updatedAt: DateTime.now(),
        partialPath: partialFile?.path,
        bytesDownloaded: bytesDownloaded,
        error: err.toString(),
      );

      if (!await _host._replace(failed, persist: true)) {
        return;
      }

      AppLogger.warning('Download failed for ${download.track.title}: $err');
    }
  }

  void _throwIfStopped(OfflineTrackDownload download) {
    final key = _host._downloadKey(download);

    if (_cancelRequested.contains(key)) {
      final latest = _host.find(download.serverBaseUrl, _host._serverTrackId(download));

      if (latest?.status == OfflineDownloadStatus.canceled) {
        throw const DownloadCanceled();
      }

      throw const DownloadPaused('download paused');
    }

    final latest = _host.find(download.serverBaseUrl, _host._serverTrackId(download));

    if (latest?.status == OfflineDownloadStatus.paused) {
      throw const DownloadPaused('download paused');
    }

    if (latest?.status == OfflineDownloadStatus.canceled) {
      throw const DownloadCanceled();
    }

    if (latest != null && _host._queuedDownloadBlockedByPausedJob(latest)) {
      throw const DownloadPaused('download job paused');
    }
  }

  Future<File> _promotePartial(File partialFile, File finalFile) async {
    try {
      return await partialFile.rename(finalFile.path);
    } on FileSystemException {
      await partialFile.copy(finalFile.path);
      await partialFile.delete();

      return finalFile;
    }
  }

  Future<DownloadWorkerComplete> _downloadOnWorker({
    required String key,
    required DownloadWorkerRequest request,
    required Future<void> Function(DownloadWorkerMetadata metadata) onMetadata,
    required Future<void> Function(DownloadWorkerProgress progress) onProgress,
  }) async {
    final receivePort = ReceivePort();
    Isolate? isolate;

    try {
      isolate = await Isolate.spawn(
        _downloadWorkerMain,
        DownloadWorkerStart(request, receivePort.sendPort),
        debugName: 'phonolite-download-worker',
      );

      await for (final message in receivePort) {
        if (message is DownloadWorkerReady) {
          _host._activeCancelPorts[key] = message.cancelPort;

          if (_cancelRequested.contains(key)) {
            message.cancelPort.send(null);
          }
        } else if (message is DownloadWorkerMetadata) {
          await onMetadata(message);
        } else if (message is DownloadWorkerProgress) {
          await onProgress(message);
        } else if (message is DownloadWorkerComplete) {
          return message;
        } else if (message is DownloadWorkerFailure) {
          if (message.kind == DownloadWorkerFailureKind.canceled) {
            final latest = _host.find(request.serverBaseUrl, request.trackId);

            if (latest?.status == OfflineDownloadStatus.canceled) {
              throw const DownloadCanceled();
            }

            throw const DownloadPaused('download paused');
          }

          if (message.kind == DownloadWorkerFailureKind.corrupt) {
            throw DownloadCorrupt(message.message);
          }

          throw Exception(message.message);
        }
      }

      throw Exception('download worker exited before completion');
    } finally {
      _host._activeCancelPorts.remove(key);
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _TrackDownloadTransferFacade {
  _TrackDownloadTransfer get _ownerTransfer;

  Set<String> get _cancelRequested => _ownerTransfer._cancelRequested;

  Future<void> _runDownload(OfflineTrackDownload queued) => _ownerTransfer._runDownload(queued);
}

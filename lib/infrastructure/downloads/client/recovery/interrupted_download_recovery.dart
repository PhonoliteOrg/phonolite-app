part of '../offline_download_client.dart';

class _InterruptedDownloadRecovery {
  final _OfflineDownloadActorCore _host;

  _InterruptedDownloadRecovery(this._host);

  Future<List<OfflineTrackDownload>> _recoverInterruptedDownloads(List<OfflineTrackDownload> downloads) async {
    final now = DateTime.now();
    final recovered = <OfflineTrackDownload>[];

    for (final download in downloads) {
      if (download.status == OfflineDownloadStatus.preparing ||
          download.status == OfflineDownloadStatus.downloading ||
          download.status == OfflineDownloadStatus.validating) {
        recovered.add(
          download.copyWith(
            // Interrupted transfers are still requested. Queue them now; the
            // scheduler waits for the restored server session before starting.
            status: OfflineDownloadStatus.queued,
            updatedAt: now,
            error: null,
          ),
        );
        continue;
      }

      if (download.status == OfflineDownloadStatus.downloaded || _downloadNeedsMissingFileRepair(download)) {
        recovered.add(await _recoverCompletedDownload(download, now));
        continue;
      }

      if (download.status == OfflineDownloadStatus.removing) {
        recovered.add(
          download.copyWith(
            status: _host._downloadFileExistsSync(download)
                ? OfflineDownloadStatus.downloaded
                : OfflineDownloadStatus.canceled,
            updatedAt: now,
            error: 'Removal interrupted',
          ),
        );
        continue;
      }

      recovered.add(download);
    }

    return recovered;
  }

  bool _downloadNeedsMissingFileRepair(OfflineTrackDownload download) {
    return download.status == OfflineDownloadStatus.corrupt && download.error == 'Completed file missing';
  }

  Future<OfflineTrackDownload> _recoverCompletedDownload(OfflineTrackDownload download, DateTime now) async {
    if (_host._downloadFileExistsSync(download)) {
      if (_downloadNeedsMissingFileRepair(download)) {
        return download.copyWith(status: OfflineDownloadStatus.downloaded, error: null);
      }

      return download;
    }

    final repairedFile = await _host._storage.findExistingTrackFile(
      serverBaseUrl: download.serverBaseUrl,
      trackId: _host._downloadFileId(download),
      extensions: _trackFileExtensionCandidates(download),
    );
    if (repairedFile != null) {
      return download.copyWith(status: OfflineDownloadStatus.downloaded, filePath: repairedFile.path, error: null);
    }

    if (_downloadNeedsMissingFileRepair(download)) {
      return download;
    }

    return download.copyWith(
      status: OfflineDownloadStatus.corrupt,
      updatedAt: now,
      filePath: null,
      error: 'Completed file missing',
    );
  }

  Iterable<String> _trackFileExtensionCandidates(OfflineTrackDownload download) sync* {
    final fileExtension = _extensionFromFilePath(download.filePath);

    if (fileExtension != null) {
      yield fileExtension;
    }

    yield OfflineLibraryStorage.extensionFromContentType(download.contentType);
    yield 'audio';
  }

  String? _extensionFromFilePath(String? filePath) {
    final trimmed = filePath?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final name = trimmed.split(RegExp(r'[/\\]')).last;
    final index = name.lastIndexOf('.');

    if (index < 0 || index == name.length - 1) {
      return null;
    }

    final extension = name.substring(index + 1).trim().toLowerCase();

    if (extension.isEmpty || extension == 'part') {
      return null;
    }

    return extension;
  }

  List<OfflineDownloadJob> _recoverInterruptedJobs(List<OfflineDownloadJob> jobs) {
    final now = DateTime.now();

    OfflineDownloadJob recoverJob(OfflineDownloadJob job) {
      if (job.status == OfflineDownloadStatus.downloading ||
          job.status == OfflineDownloadStatus.preparing ||
          job.status == OfflineDownloadStatus.validating) {
        return job.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now);
      }

      return job;
    }

    return jobs.map(recoverJob).toList(growable: false);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _InterruptedDownloadRecoveryFacade {
  _InterruptedDownloadRecovery get _ownerRecovery;

  Future<List<OfflineTrackDownload>> _recoverInterruptedDownloads(List<OfflineTrackDownload> downloads) =>
      _ownerRecovery._recoverInterruptedDownloads(downloads);

  List<OfflineDownloadJob> _recoverInterruptedJobs(List<OfflineDownloadJob> jobs) =>
      _ownerRecovery._recoverInterruptedJobs(jobs);
}

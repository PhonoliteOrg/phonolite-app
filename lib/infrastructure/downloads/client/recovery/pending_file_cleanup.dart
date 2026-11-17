part of '../offline_download_client.dart';

class _PendingFileCleanup {
  final _OfflineDownloadActorCore _host;
  Future<void>? _pendingFileCleanupFuture;
  bool _pendingFileCleanupRequested = false;

  _PendingFileCleanup(this._host);

  Future<void> _recordPendingDownloadFiles(OfflineTrackDownload download) async {
    await _host._storage.recordPendingFileDeletes(<String?>[download.filePath, download.partialPath]);
  }

  Future<void> _cleanupPendingFileDeletes() {
    final existing = _pendingFileCleanupFuture;

    if (existing != null) {
      _pendingFileCleanupRequested = true;

      return existing;
    }

    Future<void> drainPendingCleanup() async {
      do {
        _pendingFileCleanupRequested = false;
        await _runPendingFileCleanup();
      } while (_pendingFileCleanupRequested);
    }

    final future = drainPendingCleanup();

    _pendingFileCleanupFuture = future.whenComplete(() {
      _pendingFileCleanupFuture = null;
    });

    return _pendingFileCleanupFuture!;
  }

  Future<void> _runPendingFileCleanup() async {
    try {
      final paths = await _host._storage.readPendingFileDeletes();

      if (paths.isEmpty) {
        return;
      }

      for (final chunk in _host._chunks(paths, _OfflineDownloadActorCore._maxParallelFileDeletes)) {
        Future<String?> deletePendingPath(String path) async {
          final deleted = await _deletePendingFile(path);

          return deleted ? path : null;
        }

        final results = await Future.wait(chunk.map(deletePendingPath), eagerError: false);
        final completed = results.whereType<String>().toList(growable: false);

        if (completed.isNotEmpty) {
          await _host._storage.clearPendingFileDeletes(completed);
        }
      }
    } catch (err) {
      AppLogger.warning('Failed to clean up removed download files: $err');
    }
  }

  bool _downloadFileExistsSync(OfflineTrackDownload download) {
    final filePath = download.filePath;

    if (filePath == null || filePath.isEmpty) {
      return false;
    }

    return File(filePath).existsSync();
  }

  Future<bool> _deletePendingFile(String path) async {
    final trimmed = path.trim();

    if (trimmed.isEmpty) {
      return true;
    }

    try {
      if (!await _host._storage.isManagedDeletePath(trimmed)) {
        AppLogger.warning('Skipping unmanaged pending delete path outside offline storage: $trimmed');

        return true;
      }

      // Paths are deterministic, so a stale row may name a re-downloaded file.
      if (_pathAwaitsActiveTransfer(trimmed)) {
        return false;
      }

      if (_pathHeldInMemory(trimmed) || await _host._storage.isPendingFileDeleteReferenced(trimmed)) {
        return true;
      }

      final file = File(trimmed);

      if (await file.exists()) {
        await file.delete();
      }

      return true;
    } catch (err) {
      AppLogger.warning('Failed to delete removed download file $trimmed: $err');

      return false;
    }
  }

  /// Whether a current (not removing) download still names [path].
  bool _pathHeldInMemory(String path) {
    final target = _comparablePath(path);

    return _host._downloads.any(
      (download) =>
          download.status != OfflineDownloadStatus.removing &&
          (_comparablePath(download.filePath) == target || _comparablePath(download.partialPath) == target),
    );
  }

  /// Whether an in-flight transfer may promote its partial file to [path]
  /// before its completed record is persisted; the delete is retried later.
  bool _pathAwaitsActiveTransfer(String path) {
    final stem = _pathStem(_comparablePath(path));

    return _host._downloads.any(
      (download) =>
          _host._activeDownloadStatus(download.status) &&
          download.partialPath != null &&
          _pathStem(_comparablePath(download.partialPath)) == stem,
    );
  }

  String? _comparablePath(String? path) {
    final trimmed = path?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final absolute = File(trimmed).absolute.path;

    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  String? _pathStem(String? path) {
    if (path == null) {
      return null;
    }

    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');

    return dot > separator ? path.substring(0, dot) : path;
  }

  Future<void> _deleteIfExists(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PendingFileCleanupFacade {
  _PendingFileCleanup get _ownerCleanup;

  Future<void>? get _pendingFileCleanupFuture => _ownerCleanup._pendingFileCleanupFuture;

  set _pendingFileCleanupRequested(bool value) => _ownerCleanup._pendingFileCleanupRequested = value;

  Future<void> _recordPendingDownloadFiles(OfflineTrackDownload download) =>
      _ownerCleanup._recordPendingDownloadFiles(download);

  Future<void> _cleanupPendingFileDeletes() => _ownerCleanup._cleanupPendingFileDeletes();

  bool _downloadFileExistsSync(OfflineTrackDownload download) => _ownerCleanup._downloadFileExistsSync(download);

  Future<void> _deleteIfExists(String? path) => _ownerCleanup._deleteIfExists(path);
}

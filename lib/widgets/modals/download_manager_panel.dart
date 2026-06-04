import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/library_helpers.dart';
import '../../entities/app_controller.dart';
import '../../entities/models.dart';
import '../../entities/offline_download_manager.dart';
import '../../entities/offline_library.dart';
import '../display/album_row_tile.dart';
import '../display/artist_row_tile.dart';
import '../display/empty_state.dart';
import '../display/track_row_tile.dart';
import '../layouts/app_scope.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import '../ui/tech_button.dart';
import 'confirmation_modal.dart';

Future<void> showDownloadManagerPanel(BuildContext context) async {
  final controller = AppScope.of(context);
  final size = MediaQuery.of(context).size;
  if (size.width >= 820) {
    const dialogInset = EdgeInsets.symmetric(horizontal: 24, vertical: 24);
    final dialogWidth = (size.width - dialogInset.horizontal)
        .clamp(0.0, 680.0)
        .toDouble();
    final dialogHeight = (size.height - dialogInset.vertical)
        .clamp(0.0, 720.0)
        .toDouble();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return Dialog(
          insetPadding: dialogInset,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: DownloadManagerPanel(controller: controller, cut: 18),
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SizedBox(
      height: size.height * 0.92,
      child: DownloadManagerPanel(controller: controller),
    ),
  );
}

class DownloadManagerPanel extends StatelessWidget {
  const DownloadManagerPanel({
    super.key,
    this.controller,
    this.downloadsOverride,
    this.jobsOverride,
    this.cut = 0,
  }) : assert(
         controller != null ||
             downloadsOverride != null ||
             jobsOverride != null,
         'controller, downloadsOverride, or jobsOverride is required',
       );

  final AppController? controller;
  final List<OfflineTrackDownload>? downloadsOverride;
  final List<OfflineDownloadJob>? jobsOverride;
  final double cut;

  @override
  Widget build(BuildContext context) {
    final downloadsOverride = this.downloadsOverride;
    final jobsOverride = this.jobsOverride;
    if (downloadsOverride != null || jobsOverride != null) {
      return _panel(
        context,
        _DownloadManagerViewState(
          downloadsOverride ?? const <OfflineTrackDownload>[],
          jobsOverride ?? const <OfflineDownloadJob>[],
        ),
      );
    }

    return StreamBuilder<OfflineDownloadSnapshot>(
      stream: controller!.offlineDownloadSnapshotStream,
      initialData: controller!.offlineDownloadSnapshot,
      builder: (context, snapshot) {
        final state =
            snapshot.data ??
            const OfflineDownloadSnapshot(
              downloads: <OfflineTrackDownload>[],
              batches: <OfflineDownloadBatch>[],
              jobs: <OfflineDownloadJob>[],
              revision: 0,
            );
        return _panel(
          context,
          _DownloadManagerViewState(state.downloads, state.jobs),
        );
      },
    );
  }

  Widget _panel(BuildContext context, _DownloadManagerViewState state) {
    return GlassPanel(
      cut: cut,
      blur: state.hasActiveWork ? 0 : 20,
      padding: EdgeInsets.zero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          ObsidianPalette.obsidianElevated.withValues(alpha: 0.98),
          ObsidianPalette.obsidian.withValues(alpha: 0.96),
        ],
      ),
      child: SafeArea(child: _content(context, state)),
    );
  }

  Widget _content(BuildContext context, _DownloadManagerViewState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Download Manager',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TechButton(
                    label: 'Pause all',
                    icon: Icons.pause_rounded,
                    density: TechButtonDensity.compact,
                    chrome: TechButtonChrome.borderless,
                    onTap: controller == null || !state.hasPausable
                        ? null
                        : () =>
                              unawaited(controller!.pauseAllOfflineDownloads()),
                  ),
                  TechButton(
                    label: 'Resume paused',
                    icon: Icons.play_arrow_rounded,
                    density: TechButtonDensity.compact,
                    chrome: TechButtonChrome.borderless,
                    onTap: controller == null || !state.hasPaused
                        ? null
                        : () => unawaited(
                            controller!.resumePausedOfflineDownloads(),
                          ),
                  ),
                  TechButton(
                    label: 'Clear partial / failed',
                    icon: Icons.delete_sweep_rounded,
                    density: TechButtonDensity.compact,
                    chrome: TechButtonChrome.borderless,
                    onTap: controller == null || !state.hasClearable
                        ? null
                        : () => unawaited(
                            _confirmClearPausedCached(
                              context,
                              controller!,
                              state.clearableCount,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.isEmpty
              ? const EmptyStateText(
                  title: 'No queued downloads',
                  message: 'New album and artist downloads will appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: state.entries.length,
                  itemBuilder: (context, index) =>
                      _entry(context, state.entries[index]),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmClearPausedCached(
    BuildContext context,
    AppController controller,
    int clearableCount,
  ) async {
    final itemLabel = clearableCount == 1
        ? 'partial or failed download'
        : 'partial or failed downloads';
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Clear partial and failed downloads',
      message:
          'Remove $clearableCount $itemLabel from this device? Completed downloads and active downloads will not be removed.',
      confirmLabel: 'Clear',
      confirmVariant: TechButtonVariant.danger,
      actionChrome: TechButtonChrome.borderless,
    );
    if (!confirmed) {
      return;
    }
    await controller.clearPausedAndCachedOfflineDownloads();
  }

  Widget _entry(BuildContext context, _DownloadManagerEntry entry) {
    return KeyedSubtree(
      key: ValueKey(entry.key),
      child: switch (entry.kind) {
        _DownloadManagerEntryKind.jobHeader => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            'Rolling Jobs',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        _DownloadManagerEntryKind.job => _DownloadJobRow(
          job: entry.job!,
          controller: controller,
        ),
        _DownloadManagerEntryKind.sectionHeader => Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: ObsidianSectionHeader(
            title: entry.title!,
            subtitle: '${entry.count} items',
          ),
        ),
        _DownloadManagerEntryKind.download => RepaintBoundary(
          child: _DownloadItemRow(
            download: entry.download!,
            controller: controller,
          ),
        ),
        _DownloadManagerEntryKind.spacer => SizedBox(height: entry.height),
      },
    );
  }

  static int _compareQueueDownloads(
    OfflineTrackDownload left,
    OfflineTrackDownload right,
  ) {
    final status = _queueStatusRank(
      left.status,
    ).compareTo(_queueStatusRank(right.status));
    if (status != 0) {
      return status;
    }
    final priority = right.priority.compareTo(left.priority);
    if (priority != 0) {
      return priority;
    }
    return left.createdAt.compareTo(right.createdAt);
  }

  static int _queueStatusRank(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.downloading => 0,
      OfflineDownloadStatus.preparing => 1,
      OfflineDownloadStatus.validating => 2,
      OfflineDownloadStatus.queued => 3,
      _ => 4,
    };
  }

  static int _compareUpdatedNewestFirst(
    OfflineTrackDownload left,
    OfflineTrackDownload right,
  ) {
    return right.updatedAt.compareTo(left.updatedAt);
  }

  static bool _canPauseDownloadStatus(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      _ => false,
    };
  }
}

class _DownloadManagerViewState {
  _DownloadManagerViewState(
    List<OfflineTrackDownload> downloads,
    List<OfflineDownloadJob> jobs,
  ) {
    final visibleDownloads = downloads
        .where(
          (download) => download.status != OfflineDownloadStatus.downloaded,
        )
        .toList(growable: false);
    final visibleJobs = jobs
        .where(
          (job) =>
              job.status != OfflineDownloadStatus.downloaded &&
              job.status != OfflineDownloadStatus.canceled,
        )
        .toList(growable: false);
    final groups = _groups(visibleDownloads);
    final needsAttention = groups[_DownloadSection.needsAttention]!;
    final pausedDownloads = groups[_DownloadSection.paused]!;
    final pausableDownloadCount = visibleDownloads
        .where(
          (download) =>
              DownloadManagerPanel._canPauseDownloadStatus(download.status),
        )
        .length;
    final pausableJobCount = visibleJobs
        .where(
          (job) => DownloadManagerPanel._canPauseDownloadStatus(job.status),
        )
        .length;
    final pausedJobCount = visibleJobs
        .where((job) => job.status == OfflineDownloadStatus.paused)
        .length;

    hasPausable = pausableDownloadCount + pausableJobCount > 0;
    hasPaused = pausedDownloads.isNotEmpty || pausedJobCount > 0;
    clearableCount = pausedDownloads.length + needsAttention.length;
    hasClearable = clearableCount > 0;
    isEmpty = visibleDownloads.isEmpty && visibleJobs.isEmpty;
    hasActiveWork =
        visibleDownloads.any((download) => _hasActiveWork(download.status)) ||
        visibleJobs.any((job) => _hasActiveWork(job.status));
    entries = List<_DownloadManagerEntry>.unmodifiable(
      _entries(visibleJobs, groups),
    );
  }

  late final bool hasPausable;
  late final bool hasPaused;
  late final int clearableCount;
  late final bool hasClearable;
  late final bool isEmpty;
  late final bool hasActiveWork;
  late final List<_DownloadManagerEntry> entries;

  static Map<_DownloadSection, List<OfflineTrackDownload>> _groups(
    List<OfflineTrackDownload> downloads,
  ) {
    final groups = {
      _DownloadSection.queue: <OfflineTrackDownload>[],
      _DownloadSection.removing: <OfflineTrackDownload>[],
      _DownloadSection.paused: <OfflineTrackDownload>[],
      _DownloadSection.needsAttention: <OfflineTrackDownload>[],
    };
    for (final download in downloads) {
      switch (download.status) {
        case OfflineDownloadStatus.queued:
        case OfflineDownloadStatus.preparing:
        case OfflineDownloadStatus.downloading:
        case OfflineDownloadStatus.validating:
          groups[_DownloadSection.queue]!.add(download);
          break;
        case OfflineDownloadStatus.removing:
          groups[_DownloadSection.removing]!.add(download);
          break;
        case OfflineDownloadStatus.paused:
          groups[_DownloadSection.paused]!.add(download);
          break;
        case OfflineDownloadStatus.failed:
        case OfflineDownloadStatus.corrupt:
        case OfflineDownloadStatus.canceled:
          groups[_DownloadSection.needsAttention]!.add(download);
          break;
        case OfflineDownloadStatus.downloaded:
          break;
      }
    }
    groups[_DownloadSection.queue]!.sort(
      DownloadManagerPanel._compareQueueDownloads,
    );
    groups[_DownloadSection.removing]!.sort(
      DownloadManagerPanel._compareUpdatedNewestFirst,
    );
    groups[_DownloadSection.paused]!.sort(
      DownloadManagerPanel._compareUpdatedNewestFirst,
    );
    groups[_DownloadSection.needsAttention]!.sort(
      DownloadManagerPanel._compareUpdatedNewestFirst,
    );
    return groups;
  }

  static List<_DownloadManagerEntry> _entries(
    List<OfflineDownloadJob> jobs,
    Map<_DownloadSection, List<OfflineTrackDownload>> groups,
  ) {
    final entries = <_DownloadManagerEntry>[];
    if (jobs.isNotEmpty) {
      entries.add(const _DownloadManagerEntry.jobHeader());
      for (final job in jobs) {
        entries.add(_DownloadManagerEntry.job(job));
      }
      entries.add(const _DownloadManagerEntry.spacer('jobs-bottom', 12));
    }
    void addSection(_DownloadSection section, String title) {
      final downloads = groups[section]!;
      if (downloads.isEmpty) {
        return;
      }
      entries.add(
        _DownloadManagerEntry.sectionHeader(
          section.name,
          title,
          downloads.length,
        ),
      );
      for (final download in downloads) {
        entries.add(_DownloadManagerEntry.download(download));
      }
      entries.add(_DownloadManagerEntry.spacer('${section.name}-bottom', 12));
    }

    addSection(_DownloadSection.queue, 'Queue');
    addSection(_DownloadSection.removing, 'Removing');
    addSection(_DownloadSection.paused, 'Paused');
    addSection(_DownloadSection.needsAttention, 'Needs Attention');
    return entries;
  }

  static bool _hasActiveWork(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.removing => true,
      _ => false,
    };
  }
}

enum _DownloadManagerEntryKind {
  jobHeader,
  job,
  sectionHeader,
  download,
  spacer,
}

class _DownloadManagerEntry {
  const _DownloadManagerEntry._({
    required this.kind,
    required this.key,
    this.job,
    this.download,
    this.title,
    this.count = 0,
    this.height = 0,
  });

  const _DownloadManagerEntry.jobHeader()
    : this._(kind: _DownloadManagerEntryKind.jobHeader, key: 'job-header');

  _DownloadManagerEntry.job(OfflineDownloadJob job)
    : this._(
        kind: _DownloadManagerEntryKind.job,
        key: 'job:${job.jobId}',
        job: job,
      );

  _DownloadManagerEntry.sectionHeader(
    String sectionKey,
    String title,
    int count,
  ) : this._(
        kind: _DownloadManagerEntryKind.sectionHeader,
        key: 'section:$sectionKey',
        title: title,
        count: count,
      );

  _DownloadManagerEntry.download(OfflineTrackDownload download)
    : this._(
        kind: _DownloadManagerEntryKind.download,
        key:
            'download:${download.serverBaseUrl}:${download.track.serverTrackId ?? download.track.id}',
        download: download,
      );

  const _DownloadManagerEntry.spacer(String key, double height)
    : this._(
        kind: _DownloadManagerEntryKind.spacer,
        key: 'spacer:$key',
        height: height,
      );

  final _DownloadManagerEntryKind kind;
  final String key;
  final OfflineDownloadJob? job;
  final OfflineTrackDownload? download;
  final String? title;
  final int count;
  final double height;
}

class _DownloadJobRow extends StatelessWidget {
  const _DownloadJobRow({required this.job, required this.controller});

  final OfflineDownloadJob job;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    final title = _jobTitle;
    final coverUrl = _coverUrl;
    final headers = _headers;
    final trailing = _DownloadJobActions(job: job, controller: controller);
    final subtitle = _subtitle;
    if (job.kind == 'artist') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ArtistRowTile(
          artist: Artist(
            id: _sourceId ?? job.jobId,
            name: title,
            albumCount: 0,
          ),
          coverUrl: coverUrl,
          headers: headers,
          subtitle: subtitle,
          trailing: trailing,
        ),
      );
    }
    if (job.kind == 'album') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AlbumRowTile(
          album: Album(
            id: _sourceId ?? job.jobId,
            title: title,
            artist: '',
            artistId: '',
            trackCount: job.totalCount > 0
                ? job.totalCount
                : job.discoveredCount,
          ),
          coverUrl: coverUrl ?? '',
          headers: headers,
          subtitle: subtitle,
          trailing: trailing,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ArtistRowTile(
        artist: Artist(id: job.jobId, name: title, albumCount: 0),
        coverUrl: null,
        headers: const {},
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }

  String get _jobTitle {
    final label = job.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return switch (job.kind) {
      'artist' => 'Artist download',
      'album' => 'Album download',
      _ => '${job.kind} download',
    };
  }

  String get _subtitle {
    final total = job.totalCount > 0 ? job.totalCount : job.discoveredCount;
    final progress = total > 0
        ? '${job.completedCount}/$total complete'
        : '${job.discoveredCount} discovered';
    final failed = job.failedCount > 0 ? ' - ${job.failedCount} failed' : '';
    return '${job.status.name.toUpperCase()} - $progress$failed';
  }

  String? get _sourceId {
    final id = job.sourceId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String? get _coverUrl {
    final sourceId = _sourceId;
    if (sourceId == null) {
      return null;
    }
    final baseUrl = job.serverBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return null;
    }
    final encoded = Uri.encodeComponent(sourceId);
    return switch (job.kind) {
      'artist' => '$baseUrl/library/artists/$encoded/cover?kind=logo',
      'album' => '$baseUrl/library/albums/$encoded/cover',
      _ => null,
    };
  }

  Map<String, String> get _headers {
    final activeController = controller;
    if (activeController == null ||
        job.serverBaseUrl != activeController.connection.baseUrl) {
      return const {};
    }
    return authHeaders(activeController);
  }
}

class _DownloadJobActions extends StatelessWidget {
  const _DownloadJobActions({required this.job, required this.controller});

  final OfflineDownloadJob job;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          tooltip: 'Pause download job',
          icon: Icons.pause_rounded,
          onPressed: controller == null || !_canPauseJob(job)
              ? null
              : () => unawaited(controller!.pauseOfflineDownloadJob(job)),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          tooltip: 'Resume download job',
          icon: Icons.play_arrow_rounded,
          onPressed: controller == null || !_canResumeJob(job)
              ? null
              : () => unawaited(controller!.resumeOfflineDownloadJob(job)),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          tooltip: 'Cancel and remove job',
          icon: Icons.close_rounded,
          onPressed: controller == null
              ? null
              : () => unawaited(controller!.cancelOfflineDownloadJob(job)),
        ),
      ],
    );
  }

  static bool _canPauseJob(OfflineDownloadJob job) {
    return switch (job.status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      _ => false,
    };
  }

  static bool _canResumeJob(OfflineDownloadJob job) {
    return job.status == OfflineDownloadStatus.paused;
  }
}

class _DownloadItemRow extends StatelessWidget {
  const _DownloadItemRow({required this.download, required this.controller});

  final OfflineTrackDownload download;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TrackRowTile(
        track: download.track,
        index: 0,
        showIndex: false,
        showAlbumArt: true,
        showDuration: false,
        albumArtUrl: _albumArtUrl,
        albumArtHeaders: _headers,
        subtitle: _subtitle,
        offlineDownload: download,
        leading: _DownloadStatusGlyph(download: download),
        trailing: _DownloadActions(download: download, controller: controller),
      ),
    );
  }

  String get _subtitle {
    final metadata = _trackMetadataLine(download.track);
    final status = _statusText(download);
    return metadata.isEmpty ? status : '$metadata - $status';
  }

  String? get _albumArtUrl {
    final localPath = download.track.albumArtPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      return localPath;
    }
    final albumId = download.track.albumId?.trim();
    final baseUrl = download.serverBaseUrl.trim();
    if (albumId == null || albumId.isEmpty || baseUrl.isEmpty) {
      return null;
    }
    return '$baseUrl/library/albums/${Uri.encodeComponent(albumId)}/cover';
  }

  Map<String, String> get _headers {
    final activeController = controller;
    if (activeController == null ||
        download.serverBaseUrl != activeController.connection.baseUrl ||
        (download.track.albumArtPath?.trim().isNotEmpty ?? false)) {
      return const {};
    }
    return authHeaders(activeController);
  }

  String _trackMetadataLine(Track track) {
    final artist = track.artist.trim();
    final album = track.album.trim();
    if (artist.isEmpty) {
      return album;
    }
    if (album.isEmpty) {
      return artist;
    }
    return '$artist / $album';
  }

  String _statusText(OfflineTrackDownload download) {
    final status = download.status.name.toUpperCase();
    final total = download.bytesTotal;
    if (total == null || total <= 0) {
      return status;
    }
    final downloadedMb = download.bytesDownloaded / (1024 * 1024);
    final totalMb = total / (1024 * 1024);
    return '$status  ${downloadedMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
  }
}

class _DownloadStatusGlyph extends StatelessWidget {
  const _DownloadStatusGlyph({required this.download});

  final OfflineTrackDownload download;

  @override
  Widget build(BuildContext context) {
    final icon = switch (download.status) {
      OfflineDownloadStatus.queued => Icons.schedule_rounded,
      OfflineDownloadStatus.preparing => Icons.sync_rounded,
      OfflineDownloadStatus.downloading => Icons.downloading_rounded,
      OfflineDownloadStatus.paused => Icons.pause_circle_outline_rounded,
      OfflineDownloadStatus.validating => Icons.downloading_rounded,
      OfflineDownloadStatus.removing => Icons.delete_sweep_rounded,
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt => Icons.error_outline_rounded,
      OfflineDownloadStatus.canceled => Icons.cancel_outlined,
      OfflineDownloadStatus.downloaded => Icons.offline_pin_rounded,
    };
    if (download.status == OfflineDownloadStatus.downloading) {
      return SizedBox.square(
        dimension: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                value: download.progress,
                strokeWidth: 2,
                color: ObsidianPalette.gold,
                backgroundColor: ObsidianPalette.border.withValues(alpha: 0.4),
              ),
            ),
            Icon(icon, size: 14, color: ObsidianPalette.gold),
          ],
        ),
      );
    }
    final color = switch (download.status) {
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => Theme.of(context).colorScheme.error,
      OfflineDownloadStatus.downloaded => ObsidianPalette.gold,
      _ => ObsidianPalette.textMuted,
    };
    return Icon(icon, size: 22, color: color);
  }
}

class _DownloadActions extends StatelessWidget {
  const _DownloadActions({required this.download, required this.controller});

  final OfflineTrackDownload download;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    final canPause = _canPause(download.status);
    final canResume = download.status == OfflineDownloadStatus.paused;
    final canRetry = _canRetry(download.status);
    final canCancel = _canCancel(download.status);
    final canRemovePartial = _canRemovePartial(download.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          tooltip: 'Pause',
          icon: Icons.pause_rounded,
          onPressed: controller == null || !canPause
              ? null
              : () => unawaited(controller!.pauseOfflineDownload(download)),
        ),
        _ActionButton(
          tooltip: 'Resume',
          icon: Icons.play_arrow_rounded,
          onPressed: controller == null || !canResume
              ? null
              : () => unawaited(controller!.resumeOfflineDownload(download)),
        ),
        _ActionButton(
          tooltip: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: controller == null || !canRetry
              ? null
              : () => unawaited(controller!.retryOfflineDownload(download)),
        ),
        _ActionButton(
          tooltip: 'Cancel',
          icon: Icons.close_rounded,
          onPressed: controller == null || !canCancel
              ? null
              : () => unawaited(controller!.cancelOfflineDownload(download)),
        ),
        _ActionButton(
          tooltip: 'Remove partial cache',
          icon: Icons.delete_sweep_rounded,
          onPressed: controller == null || !canRemovePartial
              ? null
              : () => unawaited(controller!.removeOfflineDownload(download)),
        ),
      ],
    );
  }

  static bool _canPause(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      _ => false,
    };
  }

  static bool _canRetry(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => true,
      _ => false,
    };
  }

  static bool _canCancel(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      _ => false,
    };
  }

  static bool _canRemovePartial(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => true,
      _ => false,
    };
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

enum _DownloadSection { queue, removing, paused, needsAttention }

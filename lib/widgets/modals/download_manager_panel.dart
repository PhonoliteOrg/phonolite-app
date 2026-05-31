import 'dart:async';
import 'package:flutter/material.dart';

import '../../entities/app_controller.dart';
import '../../entities/offline_library.dart';
import '../display/empty_state.dart';
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
    return GlassPanel(
      cut: cut,
      blur: 20,
      padding: EdgeInsets.zero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          ObsidianPalette.obsidianElevated.withValues(alpha: 0.98),
          ObsidianPalette.obsidian.withValues(alpha: 0.96),
        ],
      ),
      child: SafeArea(
        child: downloadsOverride != null || jobsOverride != null
            ? _content(
                context,
                downloadsOverride ?? const <OfflineTrackDownload>[],
                jobsOverride ?? const <OfflineDownloadJob>[],
              )
            : StreamBuilder<List<OfflineTrackDownload>>(
                stream: controller!.offlineDownloadsStream,
                initialData: controller!.offlineDownloads,
                builder: (context, snapshot) {
                  final downloads =
                      snapshot.data ?? const <OfflineTrackDownload>[];
                  return StreamBuilder<List<OfflineDownloadJob>>(
                    stream: controller!.offlineDownloadJobsStream,
                    initialData: controller!.offlineDownloadJobs,
                    builder: (context, jobSnapshot) {
                      final jobs =
                          jobSnapshot.data ?? const <OfflineDownloadJob>[];
                      return _content(context, downloads, jobs);
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
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
    final pausedJobCount = visibleJobs
        .where((job) => job.status == OfflineDownloadStatus.paused)
        .length;
    final hasPaused =
        groups[_DownloadSection.paused]!.isNotEmpty || pausedJobCount > 0;
    final clearableCount =
        groups[_DownloadSection.paused]!.length + needsAttention.length;
    final hasClearable = clearableCount > 0;
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
                  TextButton.icon(
                    onPressed: controller == null || !hasPaused
                        ? null
                        : () => unawaited(
                            controller!.resumePausedOfflineDownloads(),
                          ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('RESUME PAUSED'),
                  ),
                  TextButton.icon(
                    onPressed: controller == null || !hasClearable
                        ? null
                        : () => unawaited(
                            _confirmClearPausedCached(
                              context,
                              controller!,
                              clearableCount,
                            ),
                          ),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('CLEAR PARTIAL / FAILED'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visibleDownloads.isEmpty && visibleJobs.isEmpty
              ? const EmptyStateText(
                  title: 'No queued downloads',
                  message: 'New album and artist downloads will appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _DownloadJobSectionView(
                      jobs: visibleJobs,
                      controller: controller,
                    ),
                    _DownloadSectionView(
                      title: 'Queue',
                      downloads: groups[_DownloadSection.queue]!,
                      controller: controller,
                    ),
                    _DownloadSectionView(
                      title: 'Removing',
                      downloads: groups[_DownloadSection.removing]!,
                      controller: controller,
                    ),
                    _DownloadSectionView(
                      title: 'Paused',
                      downloads: groups[_DownloadSection.paused]!,
                      controller: controller,
                    ),
                    _DownloadSectionView(
                      title: 'Needs Attention',
                      downloads: needsAttention,
                      controller: controller,
                    ),
                  ],
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
    );
    if (!confirmed) {
      return;
    }
    await controller.clearPausedAndCachedOfflineDownloads();
  }

  Map<_DownloadSection, List<OfflineTrackDownload>> _groups(
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
    groups[_DownloadSection.queue]!.sort(_compareQueueDownloads);
    groups[_DownloadSection.removing]!.sort(_compareUpdatedNewestFirst);
    groups[_DownloadSection.paused]!.sort(_compareUpdatedNewestFirst);
    groups[_DownloadSection.needsAttention]!.sort(_compareUpdatedNewestFirst);
    return groups;
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
}

class _DownloadJobSectionView extends StatelessWidget {
  const _DownloadJobSectionView({required this.jobs, required this.controller});

  final List<OfflineDownloadJob> jobs;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            'Rolling Jobs',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final job in jobs)
          _DownloadJobRow(job: job, controller: controller),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _DownloadJobRow extends StatelessWidget {
  const _DownloadJobRow({required this.job, required this.controller});

  final OfflineDownloadJob job;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    final total = job.totalCount > 0 ? job.totalCount : job.discoveredCount;
    final subtitle = total > 0
        ? '${job.completedCount}/$total complete'
        : '${job.discoveredCount} discovered';
    final failed = job.failedCount > 0 ? ' - ${job.failedCount} failed' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ObsidianCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.pending_actions_rounded, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.label ?? job.kind,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$subtitle$failed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(job.status.name.toUpperCase()),
            const SizedBox(width: 4),
            _ActionButton(
              tooltip: 'Pause artist download',
              icon: Icons.pause_rounded,
              onPressed: controller == null || !_canPauseArtistJob(job)
                  ? null
                  : () => unawaited(controller!.pauseOfflineDownloadJob(job)),
            ),
            const SizedBox(width: 4),
            _ActionButton(
              tooltip: 'Resume artist download',
              icon: Icons.play_arrow_rounded,
              onPressed: controller == null || !_canResumeArtistJob(job)
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
        ),
      ),
    );
  }

  static bool _canPauseArtistJob(OfflineDownloadJob job) {
    if (job.kind != 'artist') {
      return false;
    }
    return switch (job.status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => true,
      _ => false,
    };
  }

  static bool _canResumeArtistJob(OfflineDownloadJob job) {
    return job.kind == 'artist' && job.status == OfflineDownloadStatus.paused;
  }
}

class _DownloadSectionView extends StatelessWidget {
  const _DownloadSectionView({
    required this.title,
    required this.downloads,
    required this.controller,
  });

  final String title;
  final List<OfflineTrackDownload> downloads;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    if (downloads.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ObsidianSectionHeader(
            title: title,
            subtitle: '${downloads.length} items',
          ),
          const SizedBox(height: 10),
          ...downloads.map(
            (download) => RepaintBoundary(
              child: _DownloadItemRow(
                download: download,
                controller: controller,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadItemRow extends StatelessWidget {
  const _DownloadItemRow({required this.download, required this.controller});

  final OfflineTrackDownload download;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: ObsidianPalette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${download.track.artist} / ${download.track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: ObsidianPalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DownloadActions(download: download, controller: controller),
            ],
          ),
          const SizedBox(height: 10),
          _DownloadProgressTrack(download: download),
          const SizedBox(height: 8),
          Text(
            _statusText(download),
            style: textTheme.labelSmall?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
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

class _DownloadProgressTrack extends StatelessWidget {
  const _DownloadProgressTrack({required this.download});

  final OfflineTrackDownload download;

  @override
  Widget build(BuildContext context) {
    final progress = download.progress;
    if (download.status == OfflineDownloadStatus.downloading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          color: ObsidianPalette.gold,
        ),
      );
    }

    final fill = _fillFor(download);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            if (fill > 0)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: ObsidianPalette.gold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _fillFor(OfflineTrackDownload download) {
    final progress = download.progress;
    if (progress != null) {
      return progress;
    }
    return switch (download.status) {
      OfflineDownloadStatus.preparing => 0.08,
      OfflineDownloadStatus.downloading => 0.18,
      OfflineDownloadStatus.validating => 0.96,
      OfflineDownloadStatus.downloaded => 1.0,
      _ => 0.0,
    };
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

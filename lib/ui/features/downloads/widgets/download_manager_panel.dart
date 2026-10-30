import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/downloads/download_manager_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/downloads/download_batch.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/downloads/pending_download_track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/presentation/download_manager_entries.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_adaptive_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

Future<void> showDownloadManagerPanel(BuildContext context) async {
  final controller = AppScope.of(context);

  await ObsidianAdaptiveModal.show<void>(
    context: context,
    useCompactSheet: false,
    builder: (context, presentation) => DownloadManagerPanel(controller: controller, presentation: presentation),
  );
}

class DownloadManagerPanel extends StatelessWidget {
  final AppController? controller;
  final List<OfflineTrackDownload>? downloadsOverride;
  final List<OfflineDownloadJob>? jobsOverride;
  final List<OfflineDownloadJobItem>? jobItemsOverride;
  final ObsidianAdaptiveModalPresentation presentation;

  const DownloadManagerPanel({
    super.key,
    this.controller,
    this.downloadsOverride,
    this.jobsOverride,
    this.jobItemsOverride,
    this.presentation = ObsidianAdaptiveModalPresentation.dialog,
  }) : assert(
         controller != null || downloadsOverride != null || jobsOverride != null || jobItemsOverride != null,
         'controller or download overrides are required',
       );

  Widget _buildPanel(BuildContext context) {
    final downloadsOverride = this.downloadsOverride;
    final jobsOverride = this.jobsOverride;
    final jobItemsOverride = this.jobItemsOverride;

    if (downloadsOverride != null || jobsOverride != null || jobItemsOverride != null) {
      return _panel(
        context,
        DownloadManagerViewState(
          downloadsOverride ?? const <OfflineTrackDownload>[],
          jobsOverride ?? const <OfflineDownloadJob>[],
          jobItems: jobItemsOverride ?? const <OfflineDownloadJobItem>[],
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

        return _panel(context, DownloadManagerViewState(state.downloads, state.jobs, jobItems: state.jobItems));
      },
    );
  }

  Widget _panel(BuildContext context, DownloadManagerViewState state) {
    return ObsidianModalSurface(
      title: 'Download Manager',
      showDragHandle: presentation == ObsidianAdaptiveModalPresentation.sheet,
      headerActions: _toolbar(context, state),
      child: _content(context, state),
    );
  }

  Widget _toolbar(BuildContext context, DownloadManagerViewState state) {
    final buttonSize = ObsidianModalScope.usesTouchTargets(context) ? 44.0 : 28.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TechButton(
          label: 'Pause all',
          tooltip: 'Pause all',
          icon: PhonoliteIcons.pause,
          iconOnly: true,
          iconOnlySize: buttonSize,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: controller == null || !state.hasPausable
              ? null
              : () => unawaited(controller!.pauseAllOfflineDownloads()),
        ),
        TechButton(
          label: 'Resume paused',
          tooltip: 'Resume paused',
          icon: PhonoliteIcons.play,
          iconOnly: true,
          iconOnlySize: buttonSize,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: controller == null || !state.hasPaused
              ? null
              : () => unawaited(controller!.resumePausedOfflineDownloads()),
        ),
        TechButton(
          label: 'Clear all jobs and cache',
          tooltip: 'Clear all jobs and cache',
          icon: PhonoliteIcons.listX,
          iconOnly: true,
          iconOnlySize: buttonSize,
          density: TechButtonDensity.compact,
          chrome: TechButtonChrome.borderless,
          onTap: controller == null || state.isEmpty ? null : () => unawaited(_confirmClearAll(context, controller!)),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, DownloadManagerViewState state) {
    final entries = DownloadManagerEntries.build(state);

    return Column(
      children: [
        Expanded(
          child: state.isEmpty
              ? const EmptyStateText(
                  title: 'No queued downloads',
                  message: 'New album and artist downloads will appear here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _entry(context, entries[index]),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmClearAll(BuildContext context, AppController controller) async {
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Clear all jobs and cache',
      message:
          'Cancel unfinished download jobs and remove their partial files? Successfully downloaded songs will be kept.',
      confirmLabel: 'Clear',
      confirmVariant: TechButtonVariant.danger,
      actionChrome: TechButtonChrome.borderless,
    );

    if (!confirmed) {
      return;
    }

    await controller.clearUnfinishedOfflineDownloads();
  }

  Widget _entry(BuildContext context, DownloadManagerEntry entry) {
    return KeyedSubtree(
      key: ValueKey(entry.key),
      child: switch (entry.kind) {
        DownloadManagerEntryKind.jobHeader => Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: const ObsidianSectionHeader(title: 'Jobs'),
        ),
        DownloadManagerEntryKind.job => _DownloadJobRow(job: entry.job!, controller: controller),
        DownloadManagerEntryKind.sectionHeader => Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: ObsidianSectionHeader(title: entry.title!, subtitle: '${entry.count} items'),
        ),
        DownloadManagerEntryKind.download => RepaintBoundary(
          child: _DownloadItemRow(download: entry.download!, controller: controller),
        ),
        DownloadManagerEntryKind.pendingTrack => RepaintBoundary(
          child: _PendingDownloadItemRow(pending: entry.pendingTrack!, controller: controller),
        ),
        DownloadManagerEntryKind.spacer => SizedBox(height: entry.height),
      },
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildPanel);
}

class _DownloadJobRow extends StatelessWidget {
  final OfflineDownloadJob job;
  final AppController? controller;

  const _DownloadJobRow({required this.job, required this.controller});

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
    final progress = total > 0 ? '${job.completedCount}/$total complete' : '${job.discoveredCount} discovered';
    final failed = job.failedCount > 0 ? ' - ${job.failedCount} failed' : '';

    return '${job.status.name.toUpperCase()} - $progress$failed';
  }

  String? get _sourceId {
    final id = job.sourceId?.trim();

    return id == null || id.isEmpty ? null : id;
  }

  String? get _coverUrl => CatalogController.downloadJobCoverUrl(job);

  Map<String, String> get _headers {
    final activeController = controller;

    if (activeController == null || job.serverBaseUrl != activeController.catalog.baseUrl) {
      return const {};
    }

    return authHeaders(activeController);
  }

  Widget _buildRow(BuildContext context) {
    final title = _jobTitle;
    final coverUrl = _coverUrl;
    final headers = _headers;
    final actions = _DownloadJobActions(job: job, controller: controller);
    final subtitle = _subtitle;

    if (job.kind == 'artist') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ArtistRowTile(
          artist: Artist(id: _sourceId ?? job.jobId, name: title, albumCount: 0),
          coverUrl: coverUrl,
          headers: headers,
          subtitle: subtitle,
          trailing: actions,
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
            trackCount: job.totalCount > 0 ? job.totalCount : job.discoveredCount,
          ),
          coverUrl: coverUrl ?? '',
          headers: headers,
          subtitle: subtitle,
          trailing: actions,
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
        trailing: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = job.error?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(context),
        if (error != null && error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _DownloadJobActions extends StatelessWidget {
  final OfflineDownloadJob job;
  final AppController? controller;

  const _DownloadJobActions({required this.job, required this.controller});

  @override
  Widget build(BuildContext context) {
    final canRetry = job.profile != 'original' && job.status == OfflineDownloadStatus.failed;
    final canResume = job.status == OfflineDownloadStatus.paused || canRetry;
    final String tooltip;
    final IconData? icon;
    if (canRetry) {
      tooltip = 'Retry download job';
      icon = null;
    } else {
      tooltip = canResume ? 'Resume download job' : 'Pause download job';
      icon = canResume ? PhonoliteIcons.play : PhonoliteIcons.pause;
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _ActionButton(
          tooltip: tooltip,
          icon: icon,
          iconWidget: canRetry ? const ReloadIcon() : null,
          onPressed: controller == null || (!canResume && !DownloadManagerController.canPauseDownloadStatus(job.status))
              ? null
              : () => unawaited(
                  canResume ? controller!.resumeOfflineDownloadJob(job) : controller!.pauseOfflineDownloadJob(job),
                ),
        ),
        _ActionButton(
          tooltip: 'Cancel and remove job',
          icon: PhonoliteIcons.x,
          onPressed: controller == null ? null : () => unawaited(controller!.cancelOfflineDownloadJob(job)),
        ),
      ],
    );
  }
}

String _downloadTrackMetadataLine(Track track) {
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

class _PendingDownloadItemRow extends StatelessWidget {
  final PendingDownloadTrack pending;
  final AppController? controller;

  const _PendingDownloadItemRow({required this.pending, required this.controller});

  @override
  Widget build(BuildContext context) {
    final sourceTrack =
        pending.item.track ??
        pending.item.offlineMetadata?.track ??
        Track(
          id: pending.item.serverTrackId,
          title: 'Track ${pending.item.position + 1}',
          artist: '',
          album: pending.job.kind == 'album' ? pending.job.label ?? '' : '',
          durationMs: 0,
          liked: false,
          inPlaylists: false,
          serverBaseUrl: pending.job.serverBaseUrl,
          serverTrackId: pending.item.serverTrackId,
        );
    final track = sourceTrack.copyWith(
      serverBaseUrl: pending.job.serverBaseUrl,
      serverTrackId: pending.item.serverTrackId,
    );
    final metadata = _downloadTrackMetadataLine(track);
    final error = pending.error?.trim();
    final coverUrl =
        track.albumArtPath ?? (pending.job.kind == 'album' ? CatalogController.downloadJobCoverUrl(pending.job) : null);
    final headers =
        controller != null &&
            pending.job.serverBaseUrl == controller!.catalog.baseUrl &&
            (track.albumArtPath?.trim().isEmpty ?? true)
        ? authHeaders(controller!)
        : const <String, String>{};

    return _DownloadTrackRow(
      track: track,
      status: pending.status,
      subtitle: [metadata, if (error != null && error.isNotEmpty) error].where((part) => part.isNotEmpty).join(' - '),
      albumArtUrl: coverUrl,
      albumArtHeaders: headers,
    );
  }
}

class _DownloadItemRow extends StatelessWidget {
  final OfflineTrackDownload download;
  final AppController? controller;

  const _DownloadItemRow({required this.download, required this.controller});

  String get _subtitle {
    final metadata = _downloadTrackMetadataLine(download.track);
    final size = _downloadSizeText(download);

    return [metadata, size].where((part) => part.isNotEmpty).join(' - ');
  }

  String? get _albumArtUrl => CatalogController.downloadArtworkUrl(download);

  Map<String, String> get _headers {
    final activeController = controller;

    if (activeController == null ||
        download.serverBaseUrl != activeController.catalog.baseUrl ||
        (download.track.albumArtPath?.trim().isNotEmpty ?? false)) {
      return const {};
    }

    return authHeaders(activeController);
  }

  String _downloadSizeText(OfflineTrackDownload download) {
    final total = download.bytesTotal;

    if (total == null || total <= 0) {
      return '';
    }

    final downloadedMb = download.bytesDownloaded / (1024 * 1024);
    final totalMb = total / (1024 * 1024);

    return '${downloadedMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final actions = _DownloadRetryAction(download: download, controller: controller);

    return _DownloadTrackRow(
      track: download.track,
      status: download.status,
      subtitle: _subtitle,
      progress: download.progress,
      albumArtUrl: _albumArtUrl,
      albumArtHeaders: _headers,
      download: download,
      trailing: actions,
    );
  }
}

class _DownloadTrackRow extends StatelessWidget {
  final Track track;
  final OfflineDownloadStatus status;
  final String subtitle;
  final double? progress;
  final String? albumArtUrl;
  final Map<String, String> albumArtHeaders;
  final OfflineTrackDownload? download;
  final Widget? trailing;

  const _DownloadTrackRow({
    required this.track,
    required this.status,
    required this.subtitle,
    this.progress,
    this.albumArtUrl,
    this.albumArtHeaders = const {},
    this.download,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final row = TrackRowTile(
      track: track,
      index: 0,
      showIndex: false,
      showAlbumArt: true,
      showDuration: false,
      albumArtUrl: albumArtUrl,
      albumArtHeaders: albumArtHeaders,
      subtitle: subtitle,
      offlineDownload: download,
      downloadStatus: status,
      albumArtOverlay: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: _DownloadStatusGlyph(status: status, progress: progress),
        ),
      ),
      trailing: trailing ?? const SizedBox.shrink(),
    );

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: row);
  }
}

class _DownloadStatusGlyph extends StatelessWidget {
  final OfflineDownloadStatus status;
  final double? progress;

  const _DownloadStatusGlyph({required this.status, this.progress});

  Widget _buildGlyph(BuildContext context) {
    final icon = switch (status) {
      OfflineDownloadStatus.queued => PhonoliteIcons.clock,
      OfflineDownloadStatus.preparing => null,
      OfflineDownloadStatus.downloading => PhonoliteIcons.download,
      OfflineDownloadStatus.paused => PhonoliteIcons.circlePause,
      OfflineDownloadStatus.validating => PhonoliteIcons.download,
      OfflineDownloadStatus.removing => PhonoliteIcons.trash2,
      OfflineDownloadStatus.failed || OfflineDownloadStatus.corrupt => PhonoliteIcons.circleAlert,
      OfflineDownloadStatus.canceled => PhonoliteIcons.circleX,
      OfflineDownloadStatus.downloaded => PhonoliteIcons.circleCheck,
    };

    if (status == OfflineDownloadStatus.downloading) {
      return SizedBox.square(
        dimension: 24,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              color: ObsidianPalette.gold,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ),
      );
    }

    final color = switch (status) {
      OfflineDownloadStatus.queued || OfflineDownloadStatus.preparing => ObsidianPalette.textMuted,
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => Theme.of(context).colorScheme.error,
      OfflineDownloadStatus.downloaded => ObsidianPalette.gold,
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.removing => ObsidianPalette.textPrimary,
    };

    return status == OfflineDownloadStatus.preparing
        ? IconTheme.merge(
            data: IconThemeData(size: 22, color: color),
            child: const ReloadIcon(),
          )
        : Icon(icon, size: 22, color: color);
  }

  @override
  Widget build(BuildContext context) => Semantics(label: '${status.name} download', child: _buildGlyph(context));
}

class _DownloadRetryAction extends StatelessWidget {
  final OfflineTrackDownload download;
  final AppController? controller;

  const _DownloadRetryAction({required this.download, required this.controller});

  static bool _canRetry(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.failed || OfflineDownloadStatus.corrupt || OfflineDownloadStatus.canceled => true,
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.removing ||
      OfflineDownloadStatus.downloaded => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_canRetry(download.status)) {
      return const SizedBox.shrink();
    }

    if (ObsidianModalScope.isCompact(context)) {
      return SizedBox.square(
        dimension: 44,
        child: ObsidianOverflowActionButton(
          tooltip: 'Track actions',
          modalTitle: download.track.title,
          actions: [
            ObsidianMenuAction(
              label: 'Retry download',
              iconWidget: const ReloadIcon(),
              onTap: controller == null ? null : () => unawaited(controller!.retryOfflineDownload(download)),
            ),
          ],
        ),
      );
    }

    return _ActionButton(
      tooltip: 'Retry',
      iconWidget: const ReloadIcon(),
      onPressed: controller == null ? null : () => unawaited(controller!.retryOfflineDownload(download)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String tooltip;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;

  const _ActionButton({required this.tooltip, required this.onPressed, this.icon, this.iconWidget})
    : assert((icon == null) != (iconWidget == null));

  @override
  Widget build(BuildContext context) {
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final size = touchLayout ? 44.0 : 32.0;

    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          visualDensity: VisualDensity.standard,
          iconSize: 20,
          onPressed: withButtonHaptic(onPressed),
          icon: iconWidget ?? Icon(icon),
        ),
      ),
    );
  }
}

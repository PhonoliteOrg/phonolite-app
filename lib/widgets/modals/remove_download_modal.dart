import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../../entities/offline_library.dart';
import '../ui/tech_button.dart';
import 'confirmation_modal.dart';

Future<bool> confirmRemoveDownloadedTrack(BuildContext context, Track track) {
  return _confirmRemoveDownload(context, track.title, count: 1);
}

Future<bool> confirmRemoveDownloadedTracks(
  BuildContext context,
  Iterable<Track> tracks, {
  String? label,
}) {
  final trackList = tracks.toList(growable: false);
  final fallback = trackList.length == 1 ? trackList.single.title : 'selection';
  return _confirmRemoveDownload(
    context,
    label ?? fallback,
    count: trackList.length,
  );
}

Future<bool> confirmRemoveDownloadedDownload(
  BuildContext context,
  OfflineTrackDownload download,
) {
  return _confirmRemoveDownload(context, download.track.title, count: 1);
}

Future<bool> confirmRemoveDownloadedDownloads(
  BuildContext context,
  Iterable<OfflineTrackDownload> downloads, {
  String? label,
}) {
  final downloadList = downloads.toList(growable: false);
  final fallback = downloadList.length == 1
      ? downloadList.single.track.title
      : 'selection';
  return _confirmRemoveDownload(
    context,
    label ?? fallback,
    count: downloadList.length,
  );
}

Future<bool> _confirmRemoveDownload(
  BuildContext context,
  String rawTitle, {
  required int count,
}) {
  final title = rawTitle.trim().isEmpty ? 'this track' : rawTitle.trim();
  final target = count <= 1 ? '"$title"' : '$count downloads for $title';
  return ConfirmationModal.show(
    context,
    title: 'Remove download',
    message:
        'Remove $target from this device? This deletes downloaded audio and unused local metadata/artwork; the music stays in your server library.',
    confirmLabel: 'Remove',
    confirmVariant: TechButtonVariant.danger,
  );
}

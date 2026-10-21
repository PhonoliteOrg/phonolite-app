import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';

Future<bool> confirmRemoveDownloadedTracks(BuildContext context, Iterable<Track> tracks, {String? label}) {
  final trackList = tracks.toList(growable: false);
  final fallback = trackList.length == 1 ? trackList.single.title : 'selection';

  return _confirmRemoveDownload(context, label ?? fallback, count: trackList.length);
}

Future<bool> confirmRemoveDownloadedDownloads(
  BuildContext context,
  Iterable<OfflineTrackDownload> downloads, {
  String? label,
}) {
  final downloadList = downloads.toList(growable: false);
  final fallback = downloadList.length == 1 ? downloadList.single.track.title : 'selection';

  return _confirmRemoveDownload(context, label ?? fallback, count: downloadList.length);
}

Future<bool> _confirmRemoveDownload(BuildContext context, String rawTitle, {required int count}) {
  final title = rawTitle.trim().isEmpty ? 'this track' : rawTitle.trim();
  final target = count <= 1 ? '"$title"' : '$count downloads for $title';

  return ConfirmationModal.show(
    context,
    title: 'Remove download',
    message:
        'Remove $target from this device? This deletes downloaded audio and unused local metadata/artwork; the music stays in your server library.',
    confirmLabel: 'Remove',
    confirmVariant: TechButtonVariant.danger,
    actionChrome: TechButtonChrome.borderless,
  );
}

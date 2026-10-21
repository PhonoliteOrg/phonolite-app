import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

List<Widget> playbackBuildTechTags(PlaybackState state) {
  final tags = <Widget>[];

  if (state.shuffleMode != ShuffleMode.off) {
    tags.add(const PlaybackTechTag(label: 'SHUFFLE', highlight: true));
  }

  if (state.repeatMode == RepeatMode.one) {
    tags.add(const PlaybackTechTag(label: 'LOOP', highlight: true));
  }

  if (state.track != null) {
    tags.add(PlaybackTechTag(label: state.isLocalPlayback ? 'LOCAL' : 'SERVER', highlight: true));
  }

  final bitrate = playbackBitrateLabel(state);

  if (bitrate != null) {
    tags.add(PlaybackTechTag(label: bitrate));
  }

  final rtt = playbackRttLabel(state);

  if (rtt != null) {
    tags.add(PlaybackTechTag(label: 'PING $rtt'));
  }

  final buffer = playbackBufferAheadLabel(state);

  if (buffer != null) {
    tags.add(PlaybackTechTag(label: buffer));
  }

  return tags;
}

List<Widget> playbackBuildQueueSourceTags(PlaybackState state) {
  if (state.track == null) {
    return const [];
  }

  if (state.queueSource == PlaybackQueueSource.playlist ||
      (state.queueSource == PlaybackQueueSource.offline && state.localPlaybackSource == LocalPlaybackSource.playlist)) {
    return [
      PlaybackPlaylistSourceTag(
        playlistId: state.queueSourcePlaylistId,
        isLocal: state.queueSource == PlaybackQueueSource.offline,
      ),
    ];
  }

  final label = playbackQueueSourceLabel(state);
  if (label == null) {
    return const [];
  }

  final isLikedSource =
      state.queueSource == PlaybackQueueSource.liked ||
      (state.queueSource == PlaybackQueueSource.offline && state.localPlaybackSource == LocalPlaybackSource.liked);

  return [
    PlaybackTechTag(
      label: label,
      highlight: isLikedSource,
      outlineColor: isLikedSource ? null : playbackQueueSourceGreen.withByteOpacity(0.7),
    ),
  ];
}

class PlaybackPlaylistSourceTag extends StatelessWidget {
  final String? playlistId;
  final bool isLocal;

  const PlaybackPlaylistSourceTag({super.key, required this.playlistId, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final playlists = isLocal ? controller.localPlaylists : controller.playlists;

    return StreamBuilder<List<Playlist>>(
      stream: isLocal ? controller.localPlaylistsStream : controller.playlistsStream,
      initialData: playlists,
      builder: (context, snapshot) {
        var name = 'Playlist';

        for (final playlist in snapshot.data ?? playlists) {
          if (playlist.id == playlistId) {
            name = playlist.name;
            break;
          }
        }

        return PlaybackTechTag(label: name, outlineColor: playbackPlaylistSourcePurple.withValues(alpha: 0.7));
      },
    );
  }
}

List<Widget> playbackBuildInlineTags(PlaybackState state) {
  final sourceTags = playbackBuildQueueSourceTags(state);
  final techTags = playbackBuildTechTags(state);

  if (sourceTags.isEmpty) {
    return techTags;
  }

  if (techTags.isEmpty) {
    return sourceTags;
  }

  return [...sourceTags, ...techTags];
}

Widget playbackTechTagRow(BuildContext context, List<Widget> tags, {bool center = false, bool wrap = false}) {
  if (tags.isEmpty) {
    return const SizedBox.shrink();
  }

  double s(double value) => playbackScaled(context, value);

  if (wrap) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        runAlignment: center ? WrapAlignment.center : WrapAlignment.start,
        spacing: s(6),
        runSpacing: s(4),
        children: tags,
      ),
    );
  }

  return ConstrainedBox(
    constraints: BoxConstraints(minHeight: s(16)),
    child: ClipRect(
      child: Align(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tags.length; i++) ...[if (i > 0) SizedBox(width: s(6)), tags[i]],
            ],
          ),
        ),
      ),
    ),
  );
}

class PlaybackTechTag extends StatelessWidget {
  final String label;
  final bool highlight;
  final Color? outlineColor;

  const PlaybackTechTag({super.key, required this.label, this.highlight = false, this.outlineColor});

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final borderColor =
        outlineColor ?? (highlight ? ObsidianPalette.gold.withByteOpacity(0.6) : Colors.white.withByteOpacity(0.1));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(4), vertical: s(0.5)),
      decoration: BoxDecoration(
        color: Colors.white.withByteOpacity(0.05),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(fontSize: s(9.5), fontWeight: FontWeight.w600, letterSpacing: s(0.6)),
      ),
    );
  }
}

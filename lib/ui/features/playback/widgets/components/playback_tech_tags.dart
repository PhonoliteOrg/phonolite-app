import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_stream_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_tech_tag.dart';

List<Widget> playbackBuildTechTags(PlaybackState state) {
  final tags = <Widget>[];

  if (state.shuffleMode != ShuffleMode.off) {
    tags.add(const PlaybackTechTag(label: 'SHUFFLE', highlight: true));
  }

  if (state.repeatMode == PlaybackRepeatMode.one) {
    tags.add(const PlaybackTechTag(label: 'LOOP', highlight: true));
  }

  if (state.track != null) {
    tags.add(PlaybackTechTag(label: state.isLocalPlayback ? 'LOCAL' : 'SERVER', highlight: true));
  }

  final quality = playbackActiveQualityLabel(state);

  if (quality != null) {
    tags.add(PlaybackTechTag(label: quality));
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

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_source_tags.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_tech_tags.dart';

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

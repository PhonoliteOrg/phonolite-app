import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

const Color playbackQueueSourceGreen = Color(0xFF2ED573);

const Color playbackPlaylistSourcePurple = Color(0xFFB388FF);

const double playbackSubtitleMarqueeSpeedFactor = 0.5;

typedef ShuffleModeChanged = void Function(ShuffleMode mode, {ActionScope? scope});

double playbackScaled(BuildContext context, double value) => value * ObsidianScale.of(context);

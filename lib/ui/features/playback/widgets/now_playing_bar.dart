import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/compact_playback_footer.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_output_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_progress_bar.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_source_tags.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_track_details.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_transport_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/output_device_modal.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/shuffle_picker_modal.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/stream_quality_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

export 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart' show ShuffleModeChanged;
export 'package:phonolite_app/ui/features/playback/widgets/now_playing_expanded_sheet.dart'
    show NowPlayingExpandedSheet, showNowPlayingExpandedSheet;
export 'package:phonolite_app/ui/features/playback/widgets/now_playing_mini_bar.dart' show NowPlayingMiniBar;

class NowPlayingBar extends StatelessWidget {
  static const double _wideHeight = 147;
  static const double _compactHeight = 180;
  static const double _tightHeight = 200;
  static const double _compactWidth = 860;
  static const double _tightWidth = 520;
  static const double _wideSideWidth = 350;
  static const double _wideRowGap = 12;
  static const double _wideCommandMin = 312;

  final PlaybackState state;
  final VoidCallback? onOpenAlbum;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final ShuffleModeChanged onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;

  const NowPlayingBar({
    super.key,
    required this.state,
    required this.onOpenAlbum,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onStop,
    required this.onSeek,
    required this.onSeekPreview,
    required this.onShuffleChanged,
    required this.onToggleRepeat,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleLike,
  });

  static double heightForWidth(double width) {
    if (width < _tightWidth) {
      return _tightHeight;
    }

    if (width < _compactWidth) {
      return _compactHeight;
    }

    return _wideHeight;
  }

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final track = state.track;

    final durationSeconds = state.duration.inMilliseconds <= 0 ? 1.0 : state.duration.inMilliseconds / 1000.0;
    final maxSeconds = durationSeconds;
    final positionSeconds = (state.position.inMilliseconds / 1000.0).toDouble().clamp(0, maxSeconds).toDouble();
    final bufferedPositionSeconds = (state.bufferRatio.clamp(0.0, 1.0) * maxSeconds)
        .clamp(positionSeconds, maxSeconds)
        .toDouble();

    final techTags = <Widget>[];

    if (state.shuffleMode != ShuffleMode.off) {
      techTags.add(const PlaybackTechTag(label: 'SHUFFLE', highlight: true));
    }

    if (state.repeatMode == PlaybackRepeatMode.one) {
      techTags.add(const PlaybackTechTag(label: 'LOOP', highlight: true));
    }

    if (state.track != null) {
      techTags.add(PlaybackTechTag(label: state.isLocalPlayback ? 'LOCAL' : 'SERVER', highlight: true));
    }

    final bitrate = playbackBitrateLabel(state);

    if (bitrate != null) {
      techTags.add(PlaybackTechTag(label: bitrate));
    }

    final rtt = playbackRttLabel(state);

    if (rtt != null) {
      techTags.add(PlaybackTechTag(label: 'PING $rtt'));
    }

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(2),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(5)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withByteOpacity(0.12),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withByteOpacity(0.35),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < _compactWidth;
        final barHeight = heightForWidth(width);
        final baseRowWidth = s(_wideSideWidth) * 2 + s(_wideRowGap) * 2 + s(_wideCommandMin);
        final sideWidth = s(_wideSideWidth);
        final rowGap = s(_wideRowGap);

        final content = isCompact
            ? Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PlaybackIntelZone(
                          track: track,
                          isLoading: state.isLoading,
                          onTap: PlaybackControlsController.canOpenPlaybackDetails(state) ? onOpenAlbum : null,
                          techTags: techTags,
                          sourceTags: playbackBuildQueueSourceTags(state),
                        ),
                        SizedBox(height: s(8)),
                        PlaybackCompactControls(
                          state: state,
                          onPlayPause: onPlayPause,
                          onPrev: onPrev,
                          onNext: onNext,
                          onShuffle: () => playbackShowShuffleModal(context, onSelected: onShuffleChanged),
                          onRepeat: onToggleRepeat,
                          onAddToPlaylist: () => showAddToPlaylistModalForTrack(
                            context,
                            state.track,
                            scope: PlaybackControlsController.actionScopeForPlayback(state),
                          ),
                          onToggleLike: onToggleLike,
                          onShowDevicePicker: () => playbackShowDevicePicker(context),
                          onShowStreamMode: () => playbackShowStreamModal(
                            context,
                            current: state.streamMode,
                            onSelected: onStreamModeChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PlaybackCompactFooterRow(
                    sliderTheme: sliderTheme,
                    maxSeconds: maxSeconds,
                    position: state.position,
                    duration: state.duration,
                    animate: state.track != null && state.isPlaying && !state.isLoading,
                    bufferedPositionSeconds: bufferedPositionSeconds,
                    onSeek: onSeek,
                    onSeekPreview: onSeekPreview,
                    enabled: state.track != null,
                    volume: state.volume,
                    onVolumeChanged: onVolumeChanged,
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => FittedBox(
                        fit: BoxFit.scaleDown,
                        // Scale all three groups together, including text,
                        // artwork, slider shapes, and button hit padding.
                        child: SizedBox(
                          width: math.max(constraints.maxWidth, baseRowWidth),
                          height: constraints.maxHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: sideWidth,
                                child: PlaybackIntelZone(
                                  track: track,
                                  isLoading: state.isLoading,
                                  onTap: PlaybackControlsController.canOpenPlaybackDetails(state) ? onOpenAlbum : null,
                                  techTags: techTags,
                                  sourceTags: playbackBuildQueueSourceTags(state),
                                ),
                              ),
                              SizedBox(width: rowGap),
                              Expanded(
                                child: PlaybackCommandZone(
                                  state: state,
                                  onPlayPause: onPlayPause,
                                  onPrev: onPrev,
                                  onNext: onNext,
                                  onStop: onStop,
                                  onShuffle: () => playbackShowShuffleModal(context, onSelected: onShuffleChanged),
                                  onRepeat: onToggleRepeat,
                                ),
                              ),
                              SizedBox(width: rowGap),
                              SizedBox(
                                width: sideWidth,
                                child: PlaybackOutputZone(
                                  state: state,
                                  compact: false,
                                  onStreamModeChanged: onStreamModeChanged,
                                  onVolumeChanged: onVolumeChanged,
                                  onToggleLike: onToggleLike,
                                  onAddToPlaylist: () => showAddToPlaylistModalForTrack(
                                    context,
                                    state.track,
                                    scope: PlaybackControlsController.actionScopeForPlayback(state),
                                  ),
                                  onShowDevicePicker: () => playbackShowDevicePicker(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  PlaybackProgressBar(
                    sliderTheme: sliderTheme,
                    maxSeconds: maxSeconds,
                    position: state.position,
                    duration: state.duration,
                    animate: state.track != null && state.isPlaying && !state.isLoading,
                    bufferedPositionSeconds: bufferedPositionSeconds,
                    onSeek: onSeek,
                    onSeekPreview: onSeekPreview,
                    enabled: state.track != null,
                  ),
                ],
              );

        return Padding(
          padding: EdgeInsets.fromLTRB(s(16), s(6), s(16), s(16)),
          child: ObsidianGlassSurface(
            child: Container(
              height: barHeight,
              padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(6)),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

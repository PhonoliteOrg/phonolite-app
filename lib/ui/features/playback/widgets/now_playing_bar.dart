import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/compact_playback_footer.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/desktop_playback_frame.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/desktop_playback_layout.dart';
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
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

export 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart' show ShuffleModeChanged;
export 'package:phonolite_app/ui/features/playback/widgets/now_playing_expanded_sheet.dart'
    show NowPlayingExpandedSheet, showNowPlayingExpandedSheet;
export 'package:phonolite_app/ui/features/playback/widgets/now_playing_mini_bar.dart' show NowPlayingMiniBar;

class NowPlayingBar extends StatelessWidget {
  static const double _wideHeight = 147;
  static const double _compactHeight = 220;
  static const double _touchCompactHeight = 280;
  static const double _touchCompactWrapWidth = 720;
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
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLike;
  final bool compact;
  final bool touchTargets;
  final DesktopPlaybackLayout? desktopLayout;

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
    required this.onToggleMute,
    required this.onToggleLike,
    this.compact = false,
    this.touchTargets = false,
    this.desktopLayout,
  });

  static double heightForWidth(double width, {bool compact = false, bool touchTargets = false}) {
    if (touchTargets && compact && width < _touchCompactWrapWidth) {
      return _touchCompactHeight;
    }

    if (width < _tightWidth) {
      return _tightHeight;
    }

    if (compact || width < _compactWidth) {
      return _compactHeight;
    }

    return _wideHeight;
  }

  Widget _wideContent(
    BuildContext context, {
    required List<Widget> techTags,
    required SliderThemeData sliderTheme,
    required double maxSeconds,
    required double bufferedPositionSeconds,
    DesktopPlaybackLayout? desktopLayout,
  }) {
    double s(double value) => playbackScaled(context, value);

    final sideWidth = desktopLayout?.sideWidth ?? s(_wideSideWidth);
    final rowGap = desktopLayout == null ? s(_wideRowGap) : DesktopPlaybackLayout.rowGap;
    final baseRowWidth = sideWidth * 2 + rowGap * 2 + s(_wideCommandMin);
    final row = Row(
      children: [
        SizedBox(
          width: sideWidth,
          child: PlaybackIntelZone(
            track: state.track,
            isLoading: state.isLoading,
            onTap: PlaybackControlsController.canOpenPlaybackDetails(state) ? onOpenAlbum : null,
            techTags: techTags,
            sourceTags: playbackBuildQueueSourceTags(state),
            wrapTags: desktopLayout == null,
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
            onToggleMute: onToggleMute,
            onToggleLike: onToggleLike,
            onAddToPlaylist: () => showAddToPlaylistModalForTrack(
              context,
              state.track,
              scope: PlaybackControlsController.actionScopeForPlayback(state),
            ),
            onShowDevicePicker: () => playbackShowDevicePicker(context),
            allowWrap: desktopLayout == null,
          ),
        ),
      ],
    );

    return Column(
      children: [
        Expanded(
          child: desktopLayout != null
              ? row
              : LayoutBuilder(
                  builder: (context, constraints) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: math.max(constraints.maxWidth, baseRowWidth),
                      height: constraints.maxHeight,
                      child: row,
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
  }

  Widget _buildBar(BuildContext context, {DesktopPlaybackLayout? desktopLayout}) {
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
        final wideContent = _wideContent(
          context,
          techTags: techTags,
          sliderTheme: sliderTheme,
          maxSeconds: maxSeconds,
          bufferedPositionSeconds: bufferedPositionSeconds,
          desktopLayout: desktopLayout,
        );

        if (desktopLayout != null) {
          return DesktopPlaybackFrame(layout: desktopLayout, child: wideContent);
        }

        final isCompact = compact || width < _compactWidth;
        final barHeight = heightForWidth(width, compact: compact, touchTargets: touchTargets);

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
                          onStop: onStop,
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
                          touchTargets: touchTargets,
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
                    onToggleMute: onToggleMute,
                  ),
                ],
              )
            : wideContent;

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

  @override
  Widget build(BuildContext context) {
    if (!DesktopPlaybackLayout.supports(Theme.of(context).platform)) {
      return _buildBar(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout =
            desktopLayout ??
            DesktopPlaybackLayout.resolve(availableSize: Size(constraints.maxWidth, MediaQuery.sizeOf(context).height));

        return ObsidianScale(
          scale: 1,
          child: Builder(builder: (context) => _buildBar(context, desktopLayout: layout)),
        );
      },
    );
  }
}

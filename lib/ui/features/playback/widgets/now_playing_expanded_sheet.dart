import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_expanded_extras.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_progress_bar.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_source_tags.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_transport_controls.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_tray_transition.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/output_device_modal.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/shuffle_picker_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/marquee_text.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';

bool playbackUsesNativeMobileExpandedSheet(BuildContext context) {
  if (kIsWeb) {
    return false;
  }

  final platform = Theme.of(context).platform;

  return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
}

bool _playbackNowPlayingSheetOpen = false;

Completer<void>? _playbackNowPlayingSheetCompleter;

Future<void> showNowPlayingExpandedSheet(BuildContext context, {VoidCallback? onOpenAlbum}) async {
  final controller = AppScope.of(context);

  if (MediaQuery.of(context).size.width >= playbackCompactPlaybackChromeWidth) {
    return;
  }

  final useNativeMobileTreatment = playbackUsesNativeMobileExpandedSheet(context);

  if (_playbackNowPlayingSheetOpen) {
    return _playbackNowPlayingSheetCompleter?.future ?? Future<void>.value();
  }

  final completer = Completer<void>();

  _playbackNowPlayingSheetCompleter = completer;
  _playbackNowPlayingSheetOpen = true;

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      useSafeArea: useNativeMobileTreatment,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return PlaybackNowPlayingTrayTransition(
          child: StreamBuilder<PlaybackState>(
            stream: controller.playbackStream,
            initialData: controller.playbackState,
            builder: (context, snapshot) {
              final playback = snapshot.data ?? controller.playbackState;
              final openAlbum = onOpenAlbum;
              final expandedOpenAlbum = openAlbum == null ? null : () => _openAlbumFromSheet(sheetContext, openAlbum);

              return NowPlayingExpandedSheet(
                state: playback,
                useNativeMobileTreatment: useNativeMobileTreatment,
                onOpenAlbum: expandedOpenAlbum,
                onPlayPause: () => controller.pause(playback.isPlaying),
                onNext: controller.nextTrack,
                onPrev: controller.prevTrack,
                onStop: controller.stop,
                onSeek: controller.seekTo,
                onSeekPreview: controller.previewSeek,
                onShuffleChanged: controller.updateShuffleMode,
                onToggleRepeat: controller.toggleRepeatMode,
                onStreamModeChanged: controller.updateStreamMode,
                onVolumeChanged: controller.setVolume,
                onToggleLike: () => unawaited(PlaybackControlsController.toggleLike(controller, playback)),
              );
            },
          ),
        );
      },
    );
  } finally {
    _playbackNowPlayingSheetOpen = false;

    if (!completer.isCompleted) {
      completer.complete();
    }

    if (identical(_playbackNowPlayingSheetCompleter, completer)) {
      _playbackNowPlayingSheetCompleter = null;
    }
  }
}

void _openAlbumFromSheet(BuildContext sheetContext, VoidCallback openAlbum) {
  Navigator.of(sheetContext).pop();

  Future<void>.microtask(openAlbum);
}

class NowPlayingExpandedSheet extends StatelessWidget {
  final PlaybackState state;
  final bool useNativeMobileTreatment;
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

  const NowPlayingExpandedSheet({
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
    this.useNativeMobileTreatment = false,
  });

  Widget _buildSheet(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final usesTouchTargets = ObsidianModalScope.usesTouchTargets(context);
    final track = state.track;
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final height = useNativeMobileTreatment ? size.height : size.height * 0.92;

    final maxSeconds = state.duration.inMilliseconds <= 0 ? 1.0 : state.duration.inMilliseconds / 1000.0;
    final positionSeconds = (state.position.inMilliseconds / 1000.0).toDouble().clamp(0, maxSeconds).toDouble();
    final bufferedPositionSeconds = (state.bufferRatio.clamp(0.0, 1.0) * maxSeconds)
        .clamp(positionSeconds, maxSeconds)
        .toDouble();

    final inlineTags = playbackBuildInlineTags(state);

    final albumId = track?.albumId?.trim() ?? '';
    final canOpenAlbum = onOpenAlbum != null && PlaybackControlsController.canOpenPlaybackDetails(state);
    final localImageUrl = track?.albumArtPath?.trim();
    final hasLocalImage = localImageUrl != null && localImageUrl.isNotEmpty;
    final String? imageUrl;

    if (hasLocalImage) {
      imageUrl = localImageUrl;
    } else {
      imageUrl = albumId.isEmpty || state.isLocalPlayback
          ? null
          : AppScope.of(context).catalog.buildAlbumCoverUrl(albumId);
    }

    final headers = hasLocalImage ? const <String, String>{} : authHeaders(AppScope.of(context));
    final artSize = usesTouchTargets ? math.min(size.width - 32, 480.0) : math.min(size.width * 0.78, 320.0);

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(10),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(12)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withByteOpacity(0.12),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withByteOpacity(0.35),
    );

    Widget artwork(double artSize) => MouseRegion(
      cursor: canOpenAlbum ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: withButtonHaptic(canOpenAlbum ? onOpenAlbum : null),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: artSize,
          height: artSize,
          color: ObsidianPalette.obsidianGlass.withByteOpacity(0.6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null) AlbumArt(title: track.album, size: artSize, imageUrl: imageUrl, headers: headers),
              if (state.isLoading)
                ColoredBox(
                  color: Colors.black.withByteOpacity(0.34),
                  child: Center(
                    child: SizedBox(
                      width: s(28),
                      height: s(28),
                      child: CircularProgressIndicator(
                        strokeWidth: s(2.6),
                        valueColor: const AlwaysStoppedAnimation<Color>(ObsidianPalette.gold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final details = <Widget>[
      MarqueeText(
        text: track?.title ?? 'Nothing playing',
        style: GoogleFonts.rajdhani(fontSize: s(26), fontWeight: FontWeight.w700, letterSpacing: s(1.1)),
        velocity: s(28),
        gap: s(28),
      ),
      if (track != null) ...[
        SizedBox(height: s(10)),
        MouseRegion(
          cursor: canOpenAlbum ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: withButtonHaptic(canOpenAlbum ? onOpenAlbum : null),
            behavior: HitTestBehavior.opaque,
            child: MarqueeText(
              text: '${track.artist} - ${track.album}',
              style: GoogleFonts.poppins(fontSize: s(15), color: ObsidianPalette.textMuted),
              velocity: s(28 * playbackSubtitleMarqueeSpeedFactor),
              gap: s(24),
            ),
          ),
        ),
      ],
      if (inlineTags.isNotEmpty) ...[
        SizedBox(height: s(10)),
        playbackTechTagRow(context, inlineTags, center: true, wrap: usesTouchTargets),
      ],
      SizedBox(height: s(usesTouchTargets ? 12 : 20)),
    ];

    final sheetBody = ObsidianGlassSurface(
      // The backdrop must follow the tray, but static foreground paint can be
      // retained while the bottom-sheet route moves it on every drag frame.
      child: RepaintBoundary(
        child: Column(
          children: [
            SizedBox(height: s(12)),
            Container(
              width: s(64),
              height: s(6),
              decoration: BoxDecoration(
                color: Colors.white.withByteOpacity(0.35),
                borderRadius: BorderRadius.circular(s(6)),
              ),
            ),
            SizedBox(height: s(12)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentPadding = EdgeInsets.fromLTRB(s(16), s(12), s(16), s(12));

                  if (usesTouchTargets) {
                    return Padding(
                      padding: contentPadding,
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, artConstraints) {
                                final fittedSize = math.max(
                                  0.0,
                                  math.min(artSize, math.min(artConstraints.maxWidth, artConstraints.maxHeight)),
                                );

                                return Center(child: artwork(fittedSize));
                              },
                            ),
                          ),
                          SizedBox(height: s(22)),
                          ...details,
                        ],
                      ),
                    );
                  }

                  final contentHeight = math.max(0.0, constraints.maxHeight - contentPadding.vertical);

                  return ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: contentPadding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: contentHeight),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            artwork(artSize),
                            SizedBox(height: s(22)),
                            ...details,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                s(usesTouchTargets ? 12 : 20),
                s(6),
                s(usesTouchTargets ? 12 : 20),
                s(usesTouchTargets ? 16 : 20) + padding.bottom,
              ),
              child: Column(
                children: [
                  RepaintBoundary(
                    child: PlaybackProgressBar(
                      sliderTheme: sliderTheme,
                      maxSeconds: maxSeconds,
                      position: state.position,
                      duration: state.duration,
                      animate: track != null && state.isPlaying && !state.isLoading,
                      bufferedPositionSeconds: bufferedPositionSeconds,
                      onSeek: onSeek,
                      onSeekPreview: onSeekPreview,
                      enabled: track != null,
                    ),
                  ),
                  SizedBox(height: s(usesTouchTargets ? 18 : 22)),
                  PlaybackExpandedControls(
                    state: state,
                    onPlayPause: onPlayPause,
                    onPrev: onPrev,
                    onNext: onNext,
                    onStop: onStop,
                    onShuffle: () => playbackShowShuffleModal(context, onSelected: onShuffleChanged),
                    onRepeat: onToggleRepeat,
                  ),
                  SizedBox(height: s(usesTouchTargets ? 16 : 20)),
                  PlaybackExpandedExtras(
                    state: state,
                    onShuffle: () => playbackShowShuffleModal(context, onSelected: onShuffleChanged),
                    onToggleLike: onToggleLike,
                    onStreamModeChanged: onStreamModeChanged,
                    onVolumeChanged: onVolumeChanged,
                    onAddToPlaylist: () => showAddToPlaylistModalForTrack(
                      context,
                      state.track,
                      scope: PlaybackControlsController.actionScopeForPlayback(state),
                    ),
                    onShowDevicePicker: () => playbackShowDevicePicker(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      top: !useNativeMobileTreatment,
      bottom: !useNativeMobileTreatment,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(height: height, width: double.infinity, child: sheetBody),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildSheet);
}

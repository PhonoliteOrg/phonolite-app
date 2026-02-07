import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/app_controller.dart';
import '../../entities/models.dart';
import '../../core/library_helpers.dart';
import '../layouts/app_scope.dart';
import '../modals/add_to_playlist_modal.dart';
import '../modals/device_picker_modal.dart';
import '../ui/blur.dart';
import '../ui/hover_row.dart';
import '../ui/like_icon_button.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.onStop,
    required this.onSeek,
    required this.onShuffleChanged,
    required this.onToggleRepeat,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleLike,
  });

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<ShuffleMode> onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;

  String _formatTime(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final hh = hours.toString();
      return '$hh:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  String _shuffleLabel(ShuffleMode mode) {
    switch (mode) {
      case ShuffleMode.off:
        return 'Shuffle: Off';
      case ShuffleMode.all:
        return 'Shuffle: All';
      case ShuffleMode.artist:
        return 'Shuffle: Artist';
      case ShuffleMode.album:
        return 'Shuffle: Album';
      case ShuffleMode.custom:
        return 'Shuffle: Custom';
    }
  }

  String _streamLabel(StreamMode mode) {
    switch (mode) {
      case StreamMode.auto:
        return 'AUTO';
      case StreamMode.high:
        return 'HQ';
      case StreamMode.medium:
        return 'MQ';
      case StreamMode.low:
        return 'LQ';
    }
  }

  String? _bitrateLabel(PlaybackState state) {
    final bitrate = state.bitrateKbps;
    if (bitrate == null || bitrate.isNaN || bitrate.isInfinite || bitrate <= 0) {
      return null;
    }
    final rounded = bitrate.round();
    return '${rounded} KBPS';
  }

  String? _rttLabel(PlaybackState state) {
    final rtt = state.streamRttMs;
    if (rtt == null) {
      return null;
    }
    return '${rtt}ms';
  }

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    final durationSeconds = state.duration.inSeconds.toDouble();
    final maxSeconds = durationSeconds <= 0 ? 1.0 : durationSeconds;
    final positionSeconds =
        state.position.inSeconds.toDouble().clamp(0, maxSeconds).toDouble();
    final bufferedPositionSeconds =
        (state.bufferRatio.clamp(0.0, 1.0) * maxSeconds)
            .clamp(positionSeconds, maxSeconds)
            .toDouble();

    final techTags = <Widget>[];
    if (state.shuffleMode != ShuffleMode.off) {
      techTags.add(
        _TechTag(
          label: 'SHUFF: ${_shuffleLabel(state.shuffleMode).replaceFirst('Shuffle: ', '')}',
          highlight: true,
        ),
      );
    }
    if (state.repeatMode == RepeatMode.one) {
      techTags.add(const _TechTag(label: 'LOOP', highlight: true));
    }
    final bitrate = _bitrateLabel(state);
    if (bitrate != null) {
      techTags.add(_TechTag(label: bitrate));
    }
    final rtt = _rttLabel(state);
    if (rtt != null) {
      techTags.add(_TechTag(label: 'RTT $rtt'));
    }

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.12),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: ClipPath(
        clipper: const _HudChamferClipper(cut: 20),
        child: maybeBlur(
          sigma: 40,
          child: Container(
            height: 135,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: ObsidianPalette.obsidianElevated.withOpacity(0.85),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.2)),
                left: BorderSide(color: Colors.white.withOpacity(0.12)),
                right: BorderSide(color: Colors.white.withOpacity(0.12)),
                bottom: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.65),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 350,
                        child: _IntelZone(
                          track: track,
                          techTags: techTags,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CommandZone(
                          state: state,
                          onPlayPause: onPlayPause,
                          onPrev: onPrev,
                          onNext: onNext,
                          onStop: onStop,
                          onShuffle: () => _showShuffleModal(
                            context,
                            current: state.shuffleMode,
                            onSelected: onShuffleChanged,
                          ),
                          onRepeat: onToggleRepeat,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 350,
                        child: _OutputZone(
                          state: state,
                          onStreamModeChanged: onStreamModeChanged,
                          onVolumeChanged: onVolumeChanged,
                          onToggleLike: onToggleLike,
                          onAddToPlaylist: () => _showAddToPlaylistModal(context),
                          onShowDevicePicker: () => _showDevicePicker(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _ProgressBar(
                  sliderTheme: sliderTheme,
                  maxSeconds: maxSeconds,
                  positionSeconds: positionSeconds,
                  bufferedPositionSeconds: bufferedPositionSeconds,
                  onSeek: onSeek,
                  positionLabel: _formatTime(state.position),
                  durationLabel: _formatTime(state.duration),
                  enabled: state.track != null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showShuffleModal(
    BuildContext context, {
    required ShuffleMode current,
    required ValueChanged<ShuffleMode> onSelected,
  }) async {
    final result = await showDialog<ShuffleMode>(
      context: context,
      builder: (dialogContext) {
        final items = const [
          ShuffleMode.off,
          ShuffleMode.all,
          ShuffleMode.artist,
          ShuffleMode.album,
          ShuffleMode.custom,
        ];
        return AlertDialog(
          title: const Text('Shuffle Mode'),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: items
                  .map(
                    (mode) => ListTile(
                      title: Text(_shuffleLabel(mode)),
                      trailing: mode == current
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(dialogContext).pop(mode),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
    if (result != null && result != current) {
      onSelected(result);
    }
  }

  Future<void> _showAddToPlaylistModal(BuildContext context) async {
    final controller = AppScope.of(context);
    final track = state.track;
    if (track == null) {
      return;
    }
    if (controller.playlists.isEmpty) {
      await controller.loadPlaylists();
    }
    if (controller.playlists.isEmpty) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AddToPlaylistModal(
        playlists: controller.playlists,
        trackId: track.id,
        onSelected: (playlist) => controller.addTrackToPlaylist(playlist, track),
      ),
    );
  }

  Future<void> _showDevicePicker(BuildContext context) async {
    final controller = AppScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => DevicePickerModal(
        fetchDevices: (refresh) => controller.listOutputDevices(refresh: refresh),
        selectedId: controller.outputDeviceId,
        onSelected: (device) => controller.selectOutputDevice(device),
      ),
    );
  }
}

class _IntelZone extends StatelessWidget {
  const _IntelZone({required this.track, required this.techTags});

  final Track? track;
  final List<Widget> techTags;

  @override
  Widget build(BuildContext context) {
    final tags = techTags.isEmpty ? const [_TechTag(label: 'IDLE')] : techTags;
    return Row(
      children: [
        _AlbumArtThumb(track: track),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MarqueeText(
                key: ValueKey('title-${track?.id ?? 'idle'}'),
                text: track?.title ?? 'NO TRACK PLAYING',
                style: GoogleFonts.rajdhani(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 1),
              _MarqueeText(
                key: ValueKey('subtitle-${track?.id ?? 'idle'}'),
                text: _subtitle(track),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: ObsidianPalette.textMuted,
                ),
                velocity: 28,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 16,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < tags.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            tags[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _subtitle(Track? track) {
    if (track == null) {
      return 'IDLE';
    }
    final artist = track.artist.trim();
    final album = track.album.trim();
    if (artist.isEmpty && album.isEmpty) {
      return 'IDLE';
    }
    if (artist.isEmpty) {
      return album;
    }
    if (album.isEmpty) {
      return artist;
    }
    return '$artist - $album';
  }
}

class _AlbumArtThumb extends StatelessWidget {
  const _AlbumArtThumb({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final albumId = track?.albumId;
    final imageUrl = albumId == null || albumId.isEmpty
        ? null
        : AppScope.of(context).connection.buildAlbumCoverUrl(albumId);
    final placeholder = Container(
      color: ObsidianPalette.obsidianGlass.withOpacity(0.6),
      alignment: Alignment.center,
      child: Text(
        (track?.title.isNotEmpty == true)
            ? track!.title.substring(0, 1).toUpperCase()
            : '?',
        style: GoogleFonts.rajdhani(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final image = imageUrl == null || imageUrl.isEmpty
        ? placeholder
        : Image.network(
            imageUrl,
            headers: authHeaders(AppScope.of(context)),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );

    return ClipPath(
      clipper: const _HudChamferClipper(cut: 10),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: image,
      ),
    );
  }
}

class _CommandZone extends StatelessWidget {
  const _CommandZone({
    required this.state,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onStop,
    required this.onShuffle,
    required this.onRepeat,
  });

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ObsidianHudIconButton(
              icon: state.shuffleMode == ShuffleMode.off
                  ? Icons.shuffle_rounded
                  : Icons.shuffle_on_rounded,
              isActive: state.shuffleMode != ShuffleMode.off,
              onPressed: onShuffle,
              size: 24,
            ),
            const SizedBox(width: 6),
            ObsidianHudIconButton(
              icon: Icons.skip_previous,
              onPressed: onPrev,
              size: 26,
            ),
            const SizedBox(width: 8),
            _HudPlayButton(
              icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
              onPressed: onPlayPause,
            ),
            const SizedBox(width: 8),
            ObsidianHudIconButton(
              icon: Icons.stop_rounded,
              onPressed: onStop,
              size: 28,
            ),
            const SizedBox(width: 6),
            ObsidianHudIconButton(
              icon: Icons.skip_next,
              onPressed: onNext,
              size: 26,
            ),
            const SizedBox(width: 6),
            ObsidianHudIconButton(
              icon: Icons.repeat_rounded,
              isActive: state.repeatMode == RepeatMode.one,
              onPressed: onRepeat,
              size: 24,
            ),
          ],
        ),
      ],
    );
  }
}

class _OutputZone extends StatelessWidget {
  const _OutputZone({
    required this.state,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onShowDevicePicker,
  });

  final PlaybackState state;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowDevicePicker;

  @override
  Widget build(BuildContext context) {
    final volumeTheme = SliderTheme.of(context).copyWith(
      trackHeight: 6,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: Colors.white.withOpacity(0.6),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ObsidianHudIconButton(
                    icon: Icons.playlist_add,
                    onPressed: state.track == null ? null : onAddToPlaylist,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  LikeIconButton(
                    isLiked: state.track?.liked == true,
                    onPressed: state.track == null ? null : onToggleLike,
                    size: 26,
                  ),
                  const SizedBox(width: 16),
                  ObsidianHudIconButton(
                    icon: Icons.speaker_rounded,
                    onPressed: onShowDevicePicker,
                    size: 26,
                  ),
                  const SizedBox(width: 16),
                  _QualityBadge(
                    label: _streamLabel(state.streamMode),
                    onTap: () => _showStreamModal(
                      context,
                      current: state.streamMode,
                      onSelected: onStreamModeChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: Row(
                  children: [
                    const Icon(Icons.volume_up, size: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: volumeTheme,
                        child: Slider(
                          value: state.volume,
                          onChanged: onVolumeChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _streamLabel(StreamMode mode) {
    switch (mode) {
      case StreamMode.auto:
        return 'AUTO';
      case StreamMode.high:
        return 'HQ';
      case StreamMode.medium:
        return 'MQ';
      case StreamMode.low:
        return 'LQ';
    }
  }

  Future<void> _showStreamModal(
    BuildContext context, {
    required StreamMode current,
    required ValueChanged<StreamMode> onSelected,
  }) async {
    final result = await showDialog<StreamMode>(
      context: context,
      builder: (dialogContext) {
        final items = const [
          StreamMode.auto,
          StreamMode.high,
          StreamMode.medium,
          StreamMode.low,
        ];
        return AlertDialog(
          title: const Text('Stream Quality'),
          content: SizedBox(
            width: 320,
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: ObsidianPalette.textMuted.withOpacity(0.25),
              ),
              itemBuilder: (context, index) {
                final mode = items[index];
                final isSelected = mode == current;
                return _HudModalListRow(
                  title: _streamLabel(mode),
                  trailing: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: ObsidianPalette.gold)
                      : const SizedBox.shrink(),
                  enabled: true,
                  isSelected: isSelected,
                  onTap: () => Navigator.of(dialogContext).pop(mode),
                );
              },
            ),
          ),
        );
      },
    );
    if (result != null && result != current) {
      onSelected(result);
    }
  }
}

class _HudPlayButton extends StatefulWidget {
  const _HudPlayButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_HudPlayButton> createState() => _HudPlayButtonState();
}

class _HudPlayButtonState extends State<_HudPlayButton> {
  bool _pressed = false;
  bool _hovered = false;
  static const _transition = Duration(milliseconds: 200);

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final highlight = _hovered || _pressed;
    final glowOpacity = highlight ? 0.7 : 0.35;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: ClipPath(
          clipper: const _OctagonClipper(cutFraction: 0.3),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: glowOpacity),
            duration: _transition,
            curve: Curves.easeOut,
            builder: (context, animatedGlow, _) {
              return Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: ObsidianPalette.gold,
                  boxShadow: [
                    BoxShadow(
                      color:
                          ObsidianPalette.gold.withOpacity(animatedGlow),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: ClipPath(
                    clipper: const _OctagonClipper(cutFraction: 0.3),
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: highlight
                            ? ObsidianPalette.gold
                            : ObsidianPalette.obsidianElevated,
                      ),
                      duration: _transition,
                      curve: Curves.easeOut,
                      builder: (context, animatedFill, __) {
                        return Container(
                          color: animatedFill,
                          alignment: Alignment.center,
                          child: TweenAnimationBuilder<Color?>(
                            tween: ColorTween(
                              end: highlight
                                  ? Colors.black
                                  : ObsidianPalette.gold,
                            ),
                            duration: _transition,
                            curve: Curves.easeOut,
                            builder: (context, animatedIconColor, ___) {
                              return Icon(
                                widget.icon,
                                color: animatedIconColor,
                                size: 26,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QualityBadge extends StatefulWidget {
  const _QualityBadge({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_QualityBadge> createState() => _QualityBadgeState();
}

class _QualityBadgeState extends State<_QualityBadge> {
  bool _hovered = false;
  static const _transition = Duration(milliseconds: 200);

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _hovered
        ? ObsidianPalette.gold
        : Colors.white.withOpacity(0.05);
    final borderColor = _hovered
        ? ObsidianPalette.gold
        : Colors.white.withOpacity(0.12);
    final textColor = _hovered ? Colors.black : ObsidianPalette.gold;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _transition,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            boxShadow: [
              if (_hovered)
                BoxShadow(
                  color: ObsidianPalette.gold.withOpacity(0.35),
                  blurRadius: 10,
                ),
            ],
          ),
          child: AnimatedDefaultTextStyle(
            duration: _transition,
            curve: Curves.easeOut,
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: textColor,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.sliderTheme,
    required this.maxSeconds,
    required this.positionSeconds,
    required this.bufferedPositionSeconds,
    required this.onSeek,
    required this.positionLabel,
    required this.durationLabel,
    required this.enabled,
  });

  final SliderThemeData sliderTheme;
  final double maxSeconds;
  final double positionSeconds;
  final double bufferedPositionSeconds;
  final ValueChanged<Duration> onSeek;
  final String positionLabel;
  final String durationLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final progressTheme = sliderTheme.copyWith(
      trackHeight: 6,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      thumbColor: Colors.white,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              positionLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                letterSpacing: 1.1,
                color: ObsidianPalette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 36,
              child: SliderTheme(
                data: progressTheme,
                child: Slider(
                  value: positionSeconds,
                  max: maxSeconds,
                  secondaryTrackValue: bufferedPositionSeconds,
                  onChanged: enabled
                      ? (value) => onSeek(Duration(seconds: value.toInt()))
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              durationLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                letterSpacing: 1.1,
                color: ObsidianPalette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechTag extends StatelessWidget {
  const _TechTag({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlight
        ? ObsidianPalette.gold.withOpacity(0.6)
        : Colors.white.withOpacity(0.1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 32,
    this.gap = 24,
    this.pause = const Duration(milliseconds: 800),
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final double gap;
  final Duration pause;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _running = false;
  bool _shouldScroll = false;

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.gap != widget.gap) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
    }
  }

  @override
  void dispose() {
    _running = false;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startLoop() async {
    if (_running || !_shouldScroll) {
      return;
    }
    _running = true;
    await Future.delayed(const Duration(milliseconds: 200));
    while (mounted && _running) {
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final position = _controller.position;
      final max = position.maxScrollExtent;
      if (max <= 0) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }
      await Future.delayed(widget.pause);
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final distance = max - _controller.position.pixels;
      final durationMs = (distance / widget.velocity * 1000).round();
      await _controller.animateTo(
        max,
        duration: Duration(milliseconds: durationMs.clamp(1, 60000)),
        curve: Curves.linear,
      );
      await Future.delayed(widget.pause);
      if (!_running) {
        break;
      }
      _controller.jumpTo(0);
    }
  }

  void _setShouldScroll(bool value) {
    if (_shouldScroll == value) {
      return;
    }
    _shouldScroll = value;
    if (!_shouldScroll) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    } else {
      _startLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final shouldScroll = painter.width > constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _setShouldScroll(shouldScroll);
          }
        });

        if (!shouldScroll) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: widget.style, maxLines: 1),
                  SizedBox(width: widget.gap),
                  Text(widget.text, style: widget.style, maxLines: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudChamferClipper extends CustomClipper<Path> {
  const _HudChamferClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(covariant _HudChamferClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class _OctagonClipper extends CustomClipper<Path> {
  const _OctagonClipper({required this.cutFraction});

  final double cutFraction;

  @override
  Path getClip(Size size) {
    final cut =
        (size.shortestSide * cutFraction).clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();
  }

  @override
  bool shouldReclip(covariant _OctagonClipper oldClipper) {
    return oldClipper.cutFraction != cutFraction;
  }
}

class _HudModalListRow extends StatelessWidget {
  const _HudModalListRow({
    required this.title,
    required this.trailing,
    required this.onTap,
    required this.enabled,
    required this.isSelected,
  });

  final String title;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      onTap: onTap,
      enabled: enabled,
      isActive: isSelected,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

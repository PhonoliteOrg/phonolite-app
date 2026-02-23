import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/app_controller.dart';
import '../../entities/models.dart';
import '../../core/library_helpers.dart';
import '../layouts/app_scope.dart';
import '../layouts/obsidian_scale.dart';
import '../modals/add_to_playlist_modal.dart';
import '../modals/device_picker_modal.dart';
import '../ui/blur.dart';
import '../ui/hover_row.dart';
import '../ui/like_icon_button.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

double _scaled(BuildContext context, double value) =>
    value * ObsidianScale.of(context);

const Color _queueSourceGreen = Color(0xFF2ED573);

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
          width: _scaled(dialogContext, 320),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: _scaled(dialogContext, 4)),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: _scaled(context, 1),
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
      return 'Shuffle: Current Artist';
    case ShuffleMode.album:
      return 'Shuffle: Current Album';
    case ShuffleMode.currentPlaylist:
      return 'Shuffle: Current Playlist';
    case ShuffleMode.custom:
      return 'Shuffle: Custom';
    case ShuffleMode.liked:
      return 'Shuffle: Liked';
  }
}

bool _shuffleCanStartWithoutTrack(ShuffleMode mode) {
  return mode == ShuffleMode.all ||
      mode == ShuffleMode.custom ||
      mode == ShuffleMode.liked;
}

bool _transportControlsEnabled(PlaybackState state) {
  if (state.track != null) {
    return true;
  }
  if (state.shuffleMode == ShuffleMode.currentPlaylist) {
    return state.queueSource == PlaybackQueueSource.playlist &&
        (state.queueSourcePlaylistId?.isNotEmpty ?? false);
  }
  return _shuffleCanStartWithoutTrack(state.shuffleMode);
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

List<Widget> _buildTechTags(PlaybackState state) {
  final tags = <Widget>[];
  if (state.shuffleMode != ShuffleMode.off) {
    tags.add(
      _TechTag(
        label:
            'SHUFF: ${_shuffleLabel(state.shuffleMode).replaceFirst('Shuffle: ', '')}',
        highlight: true,
      ),
    );
  }
  if (state.repeatMode == RepeatMode.one) {
    tags.add(const _TechTag(label: 'LOOP', highlight: true));
  }
  final bitrate = _bitrateLabel(state);
  if (bitrate != null) {
    tags.add(_TechTag(label: bitrate));
  }
  final rtt = _rttLabel(state);
  if (rtt != null) {
    tags.add(_TechTag(label: 'PING $rtt'));
  }
  return tags;
}

String? _queueSourceLabel(PlaybackState state) {
  switch (state.queueSource) {
    case PlaybackQueueSource.none:
      return null;
    case PlaybackQueueSource.liked:
      return 'SOURCE: LIKED';
    case PlaybackQueueSource.playlist:
      return 'SOURCE: PLAYLIST';
  }
}

List<Widget> _buildQueueSourceTags(PlaybackState state) {
  if (state.track == null) {
    return const [];
  }
  final label = _queueSourceLabel(state);
  if (label == null) {
    return const [];
  }
  return [
    _TechTag(
      label: label,
      outlineColor: _queueSourceGreen.withOpacity(0.7),
    ),
  ];
}

List<Widget> _buildInlineTags(PlaybackState state) {
  final sourceTags = _buildQueueSourceTags(state);
  final techTags = _buildTechTags(state);
  if (sourceTags.isEmpty) {
    return techTags;
  }
  if (techTags.isEmpty) {
    return sourceTags;
  }
  return [...sourceTags, ...techTags];
}

Widget _techTagRow(
  BuildContext context,
  List<Widget> tags, {
  bool center = false,
}) {
  if (tags.isEmpty) {
    return const SizedBox.shrink();
  }
  final s = (double value) => _scaled(context, value);
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
              for (var i = 0; i < tags.length; i++) ...[
                if (i > 0) SizedBox(width: s(6)),
                tags[i],
              ],
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
  final controller = AppScope.of(context);
  if (controller.authState.isAuthorized && controller.liked.isEmpty) {
    await controller.loadLikedTracks();
  }
  final customSettings = controller.customShuffleSettings;
  final customEnabled =
      customSettings.artistIds.isNotEmpty || customSettings.genres.isNotEmpty;
  final likedEnabled = controller.liked.isNotEmpty;
  final currentPlaylistEnabled =
      controller.playbackState.queueSource == PlaybackQueueSource.playlist &&
      (controller.playbackState.queueSourcePlaylistId?.isNotEmpty ?? false);
  final result = await showDialog<ShuffleMode>(
    context: context,
    builder: (dialogContext) {
      final items = const [
        ShuffleMode.off,
        ShuffleMode.all,
        ShuffleMode.artist,
        ShuffleMode.album,
        ShuffleMode.currentPlaylist,
        ShuffleMode.custom,
        ShuffleMode.liked,
      ];
      return AlertDialog(
        title: const Text('Shuffle Mode'),
        content: SizedBox(
          width: _scaled(dialogContext, 320),
          child: ListView(
            shrinkWrap: true,
            children: items
                .map(
                  (mode) {
                    final enabled = switch (mode) {
                      ShuffleMode.custom => customEnabled,
                      ShuffleMode.liked => likedEnabled,
                      ShuffleMode.currentPlaylist => currentPlaylistEnabled,
                      _ => true,
                    };
                    return ListTile(
                      enabled: enabled,
                      title: Text(_shuffleLabel(mode)),
                      trailing: mode == current
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: enabled
                          ? () => Navigator.of(dialogContext).pop(mode)
                          : null,
                    );
                  },
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

Future<void> _showAddToPlaylistModal(
  BuildContext context,
  PlaybackState state,
) async {
  final controller = AppScope.of(context);
  final track = state.track;
  if (track == null) {
    return;
  }
  if (controller.playlists.isEmpty) {
    await controller.loadPlaylists();
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AddToPlaylistModal(
      playlists: controller.playlists,
      trackId: track.id,
      onSelected: (playlist) => controller.addTrackToPlaylist(playlist, track),
      onRemoved: (playlist) => controller.removeTrackFromPlaylist(playlist, track),
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

bool _nowPlayingSheetOpen = false;
Completer<void>? _nowPlayingSheetCompleter;

Future<void> showNowPlayingExpandedSheet(BuildContext context) async {
  final controller = AppScope.of(context);
  if (MediaQuery.of(context).size.width >= 900) {
    return;
  }
  if (_nowPlayingSheetOpen) {
    return _nowPlayingSheetCompleter?.future ?? Future<void>.value();
  }
  final completer = Completer<void>();
  _nowPlayingSheetCompleter = completer;
  _nowPlayingSheetOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (sheetContext) {
        return StreamBuilder<PlaybackState>(
          stream: controller.playbackStream,
          initialData: controller.playbackState,
          builder: (context, snapshot) {
            final playback = snapshot.data ?? controller.playbackState;
            return NowPlayingExpandedSheet(
              state: playback,
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
              onToggleLike: () {
                final track = playback.track;
                if (track != null) {
                  controller.toggleLike(track);
                }
              },
            );
          },
        );
      },
    );
  } finally {
    _nowPlayingSheetOpen = false;
    if (!completer.isCompleted) {
      completer.complete();
    }
    if (identical(_nowPlayingSheetCompleter, completer)) {
      _nowPlayingSheetCompleter = null;
    }
  }
}

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    super.key,
    required this.state,
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

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<ShuffleMode> onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;

  static const double _wideHeight = 135;
  static const double _compactHeight = 180;
  static const double _tightHeight = 200;
  static const double _compactWidth = 720;
  static const double _tightWidth = 520;
  static const double _wideSideWidth = 350;
  static const double _wideRowGap = 12;
  static const double _wideCommandMin = 230;

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
    final s = (double value) => _scaled(context, value);
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
      techTags.add(_TechTag(label: 'PING $rtt'));
    }

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(2),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(5)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.12),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < _compactWidth;
        final barHeight = heightForWidth(width);
        final innerWidth = (width - s(72)).clamp(0.0, double.infinity);
        final baseRowWidth = s(_wideSideWidth) * 2 +
            s(_wideRowGap) * 2 +
            s(_wideCommandMin);
        final denseScale =
            (innerWidth / baseRowWidth).clamp(0.7, 1.0);
        final sideWidth = s(_wideSideWidth) * denseScale;
        final rowGap = s(_wideRowGap) * denseScale;

        final content = isCompact
            ? Column(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
        _IntelZone(
          track: track,
          techTags: techTags,
          sourceTags: _buildQueueSourceTags(state),
        ),
                        SizedBox(height: s(8)),
                        _CompactControls(
                          state: state,
                          onPlayPause: onPlayPause,
                          onPrev: onPrev,
                          onNext: onNext,
                          onShuffle: () => _showShuffleModal(
                            context,
                            current: state.shuffleMode,
                            onSelected: onShuffleChanged,
                          ),
                          onRepeat: onToggleRepeat,
                          onAddToPlaylist: () =>
                              _showAddToPlaylistModal(context, state),
                          onToggleLike: onToggleLike,
                          onShowDevicePicker: () => _showDevicePicker(context),
                          onShowStreamMode: () => _showStreamModal(
                            context,
                            current: state.streamMode,
                            onSelected: onStreamModeChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CompactFooterRow(
                    sliderTheme: sliderTheme,
                    maxSeconds: maxSeconds,
                    positionSeconds: positionSeconds,
                    bufferedPositionSeconds: bufferedPositionSeconds,
                    onSeek: onSeek,
                    onSeekPreview: onSeekPreview,
                    positionLabel: _formatTime(state.position),
                    durationLabel: _formatTime(state.duration),
                    enabled: state.track != null,
                    volume: state.volume,
                    onVolumeChanged: onVolumeChanged,
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: sideWidth,
                          child: _IntelZone(
                            track: track,
                            techTags: techTags,
                            sourceTags: _buildQueueSourceTags(state),
                          ),
                        ),
                        SizedBox(width: rowGap),
                        Expanded(
                          child: _CommandZone(
                            state: state,
                            onPlayPause: onPlayPause,
                            onPrev: onPrev,
                            onNext: onNext,
                            onStop: onStop,
                            density: denseScale,
                            onShuffle: () => _showShuffleModal(
                              context,
                              current: state.shuffleMode,
                              onSelected: onShuffleChanged,
                            ),
                            onRepeat: onToggleRepeat,
                          ),
                        ),
                        SizedBox(width: rowGap),
                        SizedBox(
                          width: sideWidth,
                          child: _OutputZone(
                            state: state,
                            compact: false,
                            density: denseScale,
                            onStreamModeChanged: onStreamModeChanged,
                            onVolumeChanged: onVolumeChanged,
                            onToggleLike: onToggleLike,
                            onAddToPlaylist: () =>
                                _showAddToPlaylistModal(context, state),
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
                    onSeekPreview: onSeekPreview,
                    positionLabel: _formatTime(state.position),
                    durationLabel: _formatTime(state.duration),
                    enabled: state.track != null,
                  ),
                ],
              );

        return Padding(
          padding: EdgeInsets.fromLTRB(s(16), s(6), s(16), s(16)),
          child: ClipPath(
            clipper: _HudChamferClipper(cut: s(20)),
            child: maybeBlur(
              sigma: 40,
              child: Container(
                height: barHeight,
                padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(6)),
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
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class NowPlayingMiniBar extends StatelessWidget {
  const NowPlayingMiniBar({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onExpand,
  });

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onExpand;

  static const double _height = 72;

  static double heightForWidth(double width) => _height;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final track = state.track;
    final transportEnabled = _transportControlsEnabled(state);
    final subtitle = track == null ? 'IDLE' : _miniSubtitle(track);
    final inlineTags = _buildInlineTags(state);
    final tags = inlineTags.isEmpty ? const [_TechTag(label: 'IDLE')] : inlineTags;
    final albumId = track?.albumId;
    final imageUrl = albumId == null || albumId.isEmpty
        ? null
        : AppScope.of(context).connection.buildAlbumCoverUrl(albumId);
    final headers = authHeaders(AppScope.of(context));
    final artSize = s(54);
    final playSize = s(60);

    return Padding(
      padding: EdgeInsets.fromLTRB(s(12), 0, s(12), s(12)),
      child: ClipPath(
        clipper: _HudChamferClipper(cut: s(18)),
        child: Material(
          color: ObsidianPalette.obsidianElevated.withOpacity(0.9),
          child: InkWell(
            onTap: onExpand,
            child: Container(
              height: _height,
              padding: EdgeInsets.symmetric(horizontal: s(14)),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.15)),
                  left: BorderSide(color: Colors.white.withOpacity(0.1)),
                  right: BorderSide(color: Colors.white.withOpacity(0.1)),
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  ClipPath(
                    clipper: _HudChamferClipper(cut: s(8)),
                    child: Container(
                      width: artSize,
                      height: artSize,
                      decoration: BoxDecoration(
                        color: ObsidianPalette.obsidianGlass.withOpacity(0.6),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: imageUrl == null
                          ? (track == null
                              ? Icon(
                                  Icons.music_note_rounded,
                                  color: ObsidianPalette.textMuted,
                                  size: artSize * 0.5,
                                )
                              : const SizedBox.shrink())
                          : Image.network(
                              imageUrl,
                              headers: headers,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                    ),
                  ),
                  SizedBox(width: s(12)),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MarqueeText(
                          text: track?.title ?? 'NO TRACK PLAYING',
                          style: GoogleFonts.rajdhani(
                            fontSize: s(16),
                            fontWeight: FontWeight.w700,
                            letterSpacing: s(0.8),
                          ),
                          velocity: s(26),
                          gap: s(20),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          SizedBox(height: s(2)),
                          _MarqueeText(
                            text: subtitle,
                            style: GoogleFonts.poppins(
                              fontSize: s(12),
                              color: ObsidianPalette.textMuted,
                            ),
                            velocity: s(24),
                            gap: s(18),
                          ),
                        ],
                        if (tags.isNotEmpty) ...[
                          SizedBox(height: s(4)),
                          _techTagRow(context, tags),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: transportEnabled ? onPlayPause : null,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.all(s(10)),
                      child: _HudPlayButton(
                        icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                        onPressed: transportEnabled ? onPlayPause : null,
                        size: playSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _miniSubtitle(Track track) {
    final artist = track.artist.trim();
    final album = track.album.trim();
    if (artist.isEmpty && album.isEmpty) {
      return '';
    }
    if (artist.isEmpty) {
      return album;
    }
    if (album.isEmpty) {
      return artist;
    }
    return '$artist • $album';
  }
}

class NowPlayingExpandedSheet extends StatelessWidget {
  const NowPlayingExpandedSheet({
    super.key,
    required this.state,
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

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<ShuffleMode> onShuffleChanged;
  final VoidCallback onToggleRepeat;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final track = state.track;
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final height = size.height * 0.92;
    final maxSeconds = math.max(1, state.duration.inSeconds).toDouble();
    final positionSeconds =
        state.position.inSeconds.toDouble().clamp(0, maxSeconds).toDouble();
    final bufferedPositionSeconds = (state.bufferRatio.clamp(0.0, 1.0) *
            maxSeconds)
        .clamp(positionSeconds, maxSeconds)
        .toDouble();
    final inlineTags = _buildInlineTags(state);

    final albumId = track?.albumId ?? '';
    final imageUrl = albumId.isEmpty
        ? null
        : AppScope.of(context).connection.buildAlbumCoverUrl(albumId);
    final headers = authHeaders(AppScope.of(context));
    final artSize = math.min(size.width * 0.78, 320.0);

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(10),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(12)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.12),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );

    return SafeArea(
      top: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: height,
          child: ClipPath(
            clipper: _HudChamferClipper(cut: s(24)),
            child: maybeBlur(
              sigma: 40,
              child: Container(
                color: ObsidianPalette.obsidianElevated.withOpacity(0.95),
                child: Column(
                  children: [
                    SizedBox(height: s(12)),
                    Container(
                      width: s(64),
                      height: s(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(s(6)),
                      ),
                    ),
                    SizedBox(height: s(12)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              s(16),
                              s(12),
                              s(16),
                              s(12),
                            ),
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: constraints.maxHeight),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: artSize,
                                    height: artSize,
                                    decoration: BoxDecoration(
                                      color: ObsidianPalette.obsidianGlass
                                          .withOpacity(0.6),
                                      border: Border.all(
                                          color: Colors.white.withOpacity(0.18)),
                                    ),
                                    child: imageUrl == null
                                        ? const SizedBox.shrink()
                                        : Image.network(
                                            imageUrl,
                                            headers: headers,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox.shrink(),
                                          ),
                                  ),
                                  SizedBox(height: s(22)),
                                  _MarqueeText(
                                    text: track?.title ?? 'Nothing playing',
                                    style: GoogleFonts.rajdhani(
                                      fontSize: s(26),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: s(1.1),
                                    ),
                                    velocity: s(28),
                                    gap: s(28),
                                  ),
                                  if (track != null) ...[
                                    SizedBox(height: s(10)),
                                    _MarqueeText(
                                      text: '${track.artist} • ${track.album}',
                                      style: GoogleFonts.poppins(
                                        fontSize: s(15),
                                        color: ObsidianPalette.textMuted,
                                      ),
                                      velocity: s(26),
                                      gap: s(24),
                                    ),
                                  ],
                                  if (inlineTags.isNotEmpty) ...[
                                    SizedBox(height: s(10)),
                                    _techTagRow(context, inlineTags, center: true),
                                  ],
                                  SizedBox(height: s(20)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        s(20),
                        s(6),
                        s(20),
                        s(20) + padding.bottom,
                      ),
                      child: Column(
                        children: [
                          _ProgressBar(
                            sliderTheme: sliderTheme,
                            maxSeconds: maxSeconds,
                            positionSeconds: positionSeconds,
                            bufferedPositionSeconds: bufferedPositionSeconds,
                            onSeek: onSeek,
                            onSeekPreview: onSeekPreview,
                            positionLabel: _formatTime(state.position),
                            durationLabel: _formatTime(state.duration),
                            enabled: track != null,
                          ),
                          SizedBox(height: s(22)),
                          _ExpandedControls(
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
                          SizedBox(height: s(20)),
                          _ExpandedExtras(
                            state: state,
                            onToggleLike: onToggleLike,
                            onStreamModeChanged: onStreamModeChanged,
                            onVolumeChanged: onVolumeChanged,
                            onAddToPlaylist: () =>
                                _showAddToPlaylistModal(context, state),
                            onShowDevicePicker: () => _showDevicePicker(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntelZone extends StatelessWidget {
  const _IntelZone({
    required this.track,
    required this.techTags,
    required this.sourceTags,
  });

  final Track? track;
  final List<Widget> techTags;
  final List<Widget> sourceTags;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final tags = techTags.isEmpty ? const [_TechTag(label: 'IDLE')] : techTags;
    return Row(
      children: [
        _AlbumArtThumb(track: track),
        SizedBox(width: s(12)),
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
                  fontSize: s(17),
                  fontWeight: FontWeight.w700,
                  letterSpacing: s(1.0),
                ),
                velocity: s(32),
                gap: s(24),
              ),
              SizedBox(height: s(1)),
              _MarqueeText(
                key: ValueKey('subtitle-${track?.id ?? 'idle'}'),
                text: _subtitle(track),
                style: GoogleFonts.poppins(
                  fontSize: s(11),
                  color: ObsidianPalette.textMuted,
                ),
                velocity: s(28),
                gap: s(24),
              ),
              SizedBox(height: s(4)),
              _techTagRow(context, tags),
              if (sourceTags.isNotEmpty) ...[
                SizedBox(height: s(4)),
                _techTagRow(context, sourceTags),
              ],
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
    final s = (double value) => _scaled(context, value);
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
          fontSize: s(20),
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
      clipper: _HudChamferClipper(cut: s(10)),
      child: Container(
        width: s(64),
        height: s(64),
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
    this.density = 1.0,
  });

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final double density;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final d = density;
    final transportEnabled = _transportControlsEnabled(state);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ObsidianHudIconButton(
                    icon: state.shuffleMode == ShuffleMode.off
                        ? Icons.shuffle_rounded
                        : Icons.shuffle_on_rounded,
                    isActive: state.shuffleMode != ShuffleMode.off,
                    onPressed: onShuffle,
                    size: s(24 * d),
                  ),
                  SizedBox(width: s(6 * d)),
                  ObsidianHudIconButton(
                    icon: Icons.skip_previous,
                    onPressed: transportEnabled ? onPrev : null,
                    size: s(26 * d),
                  ),
                  SizedBox(width: s(8 * d)),
                  _HudPlayButton(
                    icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                    onPressed: transportEnabled ? onPlayPause : null,
                    size: 54 * d,
                  ),
                  SizedBox(width: s(8 * d)),
                  ObsidianHudIconButton(
                    icon: Icons.stop_rounded,
                    onPressed: transportEnabled ? onStop : null,
                    size: s(28 * d),
                  ),
                  SizedBox(width: s(6 * d)),
                  ObsidianHudIconButton(
                    icon: Icons.skip_next,
                    onPressed: transportEnabled ? onNext : null,
                    size: s(26 * d),
                  ),
                  SizedBox(width: s(6 * d)),
                  ObsidianHudIconButton(
                    icon: Icons.repeat_rounded,
                    isActive: state.repeatMode == RepeatMode.one,
                    onPressed: onRepeat,
                    size: s(24 * d),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ExpandedControls extends StatelessWidget {
  const _ExpandedControls({
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
    final s = (double value) => _scaled(context, value);
    final transportEnabled = _transportControlsEnabled(state);

    final leftRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          icon: state.shuffleMode == ShuffleMode.off
              ? Icons.shuffle_rounded
              : Icons.shuffle_on_rounded,
          isActive: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: s(32),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          icon: Icons.skip_previous,
          onPressed: transportEnabled ? onPrev : null,
          size: s(38),
        ),
      ],
    );
    final rightRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          icon: Icons.skip_next,
          onPressed: transportEnabled ? onNext : null,
          size: s(38),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          icon: Icons.stop_rounded,
          onPressed: transportEnabled ? onStop : null,
          size: s(38),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          icon: Icons.repeat_rounded,
          isActive: state.repeatMode == RepeatMode.one,
          onPressed: onRepeat,
          size: s(32),
        ),
      ],
    );

    return SizedBox(
      height: s(96),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final rawPlaySize = s(98);
          final playSize = math.min(rawPlaySize, maxWidth);
          final maxGap = ((maxWidth - playSize) / 2).clamp(0.0, double.infinity);
          final gap = math.min(s(12), maxGap);
          final sideWidth = ((maxWidth - playSize - gap * 2) / 2)
              .clamp(0.0, double.infinity);

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: leftRow,
                  ),
                ),
              ),
              SizedBox(width: gap),
              _HudPlayButton(
                icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: transportEnabled ? onPlayPause : null,
                size: playSize,
              ),
              SizedBox(width: gap),
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: rightRow,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExpandedExtras extends StatelessWidget {
  const _ExpandedExtras({
    required this.state,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onShowDevicePicker,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
  });

  final PlaybackState state;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowDevicePicker;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final trackAvailable = state.track != null;
    final volumeTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(7),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(10)),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: Colors.white.withOpacity(0.6),
    );

    final actions = <Widget>[
      ObsidianHudIconButton(
        icon: Icons.playlist_add,
        onPressed: trackAvailable ? onAddToPlaylist : null,
        size: s(32),
      ),
      LikeIconButton(
        isLiked: state.track?.liked == true,
        onPressed: trackAvailable ? onToggleLike : null,
        size: s(32),
      ),
      ObsidianHudIconButton(
        icon: Icons.speaker_rounded,
        onPressed: onShowDevicePicker,
        size: s(32),
      ),
      _QualityBadge(
        label: _streamLabel(state.streamMode),
        onTap: () => _showStreamModal(
          context,
          current: state.streamMode,
          onSelected: onStreamModeChanged,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: s(48),
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) SizedBox(width: s(14)),
                    actions[i],
                  ],
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: s(14)),
        Row(
          children: [
            Icon(Icons.volume_up, size: s(28), color: ObsidianPalette.textMuted),
            SizedBox(width: s(8)),
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
      ],
    );
  }
}

class _CompactControls extends StatelessWidget {
  const _CompactControls({
    required this.state,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onRepeat,
    required this.onAddToPlaylist,
    required this.onToggleLike,
    required this.onShowDevicePicker,
    required this.onShowStreamMode,
  });

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onToggleLike;
  final VoidCallback onShowDevicePicker;
  final VoidCallback onShowStreamMode;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final scale = ObsidianScale.of(context);
    final playSize = 64 / scale;
    final transportEnabled = _transportControlsEnabled(state);
    final trackAvailable = state.track != null;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: s(8),
      runSpacing: s(8),
      children: [
        ObsidianHudIconButton(
          icon: state.shuffleMode == ShuffleMode.off
              ? Icons.shuffle_rounded
              : Icons.shuffle_on_rounded,
          isActive: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: s(22),
        ),
        ObsidianHudIconButton(
          icon: Icons.skip_previous,
          onPressed: transportEnabled ? onPrev : null,
          size: s(24),
        ),
        _HudPlayButton(
          icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: transportEnabled ? onPlayPause : null,
          size: playSize,
        ),
        ObsidianHudIconButton(
          icon: Icons.skip_next,
          onPressed: transportEnabled ? onNext : null,
          size: s(24),
        ),
        ObsidianHudIconButton(
          icon: Icons.repeat_rounded,
          isActive: state.repeatMode == RepeatMode.one,
          onPressed: onRepeat,
          size: s(22),
        ),
        ObsidianHudIconButton(
          icon: Icons.playlist_add,
          onPressed: trackAvailable ? onAddToPlaylist : null,
          size: s(22),
        ),
        LikeIconButton(
          isLiked: state.track?.liked == true,
          onPressed: trackAvailable ? onToggleLike : null,
          size: s(22),
        ),
        ObsidianHudIconButton(
          icon: Icons.speaker_rounded,
          onPressed: onShowDevicePicker,
          size: s(22),
        ),
        _QualityBadge(
          label: _streamLabel(state.streamMode),
          onTap: onShowStreamMode,
        ),
      ],
    );
  }
}

class _CompactFooterRow extends StatelessWidget {
  const _CompactFooterRow({
    required this.sliderTheme,
    required this.maxSeconds,
    required this.positionSeconds,
    required this.bufferedPositionSeconds,
    required this.onSeek,
    required this.onSeekPreview,
    required this.positionLabel,
    required this.durationLabel,
    required this.enabled,
    required this.volume,
    required this.onVolumeChanged,
  });

  final SliderThemeData sliderTheme;
  final double maxSeconds;
  final double positionSeconds;
  final double bufferedPositionSeconds;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final String positionLabel;
  final String durationLabel;
  final bool enabled;
  final double volume;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final progressTheme = sliderTheme.copyWith(
      trackHeight: s(5),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(6)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );
    final volumeTheme = sliderTheme.copyWith(
      trackHeight: s(4),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(5)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: Colors.white.withOpacity(0.6),
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: s(28),
                child: SliderTheme(
                  data: progressTheme,
                  child: Slider(
                    value: positionSeconds,
                    max: maxSeconds,
                    secondaryTrackValue: bufferedPositionSeconds,
                    onChanged: enabled
                        ? (value) => onSeekPreview(Duration(seconds: value.toInt()))
                        : null,
                    onChangeEnd: enabled
                        ? (value) => onSeek(Duration(seconds: value.toInt()))
                        : null,
                  ),
                ),
              ),
              SizedBox(height: s(2)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    positionLabel,
                    style: GoogleFonts.rajdhani(
                      fontSize: s(12),
                      letterSpacing: s(0.8),
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                  Text(
                    durationLabel,
                    style: GoogleFonts.rajdhani(
                      fontSize: s(12),
                      letterSpacing: s(0.8),
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: s(10)),
        SizedBox(
          width: s(110),
          child: Row(
            children: [
              Icon(Icons.volume_up, size: s(18), color: ObsidianPalette.textMuted),
              SizedBox(width: s(6)),
              Expanded(
                child: SliderTheme(
                  data: volumeTheme,
                  child: Slider(
                    value: volume,
                    onChanged: onVolumeChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutputZone extends StatelessWidget {
  const _OutputZone({
    required this.state,
    required this.compact,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onShowDevicePicker,
    this.density = 1.0,
  });

  final PlaybackState state;
  final bool compact;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowDevicePicker;
  final double density;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final d = density;
    final volumeTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(6 * d),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(8 * d)),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: Colors.white.withOpacity(0.6),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = compact || constraints.maxWidth < s(320 * d);
        final controlSpacing = isTight ? s(10 * d) : s(16 * d);
        final controls = <Widget>[
          ObsidianHudIconButton(
            icon: Icons.playlist_add,
            onPressed: state.track == null ? null : onAddToPlaylist,
            size: s(26 * d),
          ),
          LikeIconButton(
            isLiked: state.track?.liked == true,
            onPressed: state.track == null ? null : onToggleLike,
            size: s(26 * d),
          ),
          ObsidianHudIconButton(
            icon: Icons.speaker_rounded,
            onPressed: onShowDevicePicker,
            size: s(26 * d),
          ),
          _QualityBadge(
            label: _streamLabel(state.streamMode),
            onTap: () => _showStreamModal(
              context,
              current: state.streamMode,
              onSelected: onStreamModeChanged,
            ),
          ),
        ];
        final controlsRow = isTight
            ? Wrap(
                alignment: compact ? WrapAlignment.center : WrapAlignment.end,
                spacing: controlSpacing,
                runSpacing: s(6),
                children: controls,
              )
            : Row(
                mainAxisAlignment:
                    compact ? MainAxisAlignment.center : MainAxisAlignment.end,
                children: [
                  controls[0],
                  SizedBox(width: s(14 * d)),
                  controls[1],
                  SizedBox(width: controlSpacing),
                  controls[2],
                  SizedBox(width: controlSpacing),
                  controls[3],
                ],
              );

        final sliderWidth = isTight ? constraints.maxWidth : s(200 * d);
        final sliderRow = Align(
          alignment:
              compact ? Alignment.center : Alignment.centerRight,
          child: SizedBox(
            width: sliderWidth,
            child: Row(
              children: [
                Icon(Icons.volume_up, size: s(26 * d)),
                SizedBox(width: s(8 * d)),
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
        );

        return Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment:
                    compact ? CrossAxisAlignment.center : CrossAxisAlignment.end,
                children: [
                  controlsRow,
                  SizedBox(height: s(8)),
                  sliderRow,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

}

class _HudPlayButton extends StatefulWidget {
  const _HudPlayButton({
    required this.icon,
    required this.onPressed,
    this.size = 54,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<_HudPlayButton> createState() => _HudPlayButtonState();
}

class _HudPlayButtonState extends State<_HudPlayButton> {
  bool _pressed = false;
  bool _hovered = false;
  static const _transition = Duration(milliseconds: 200);

  @override
  void didUpdateWidget(covariant _HudPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPressed != null && widget.onPressed == null) {
      if (_pressed || _hovered) {
        setState(() {
          _pressed = false;
          _hovered = false;
        });
      }
    }
  }

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
    final s = (double value) => _scaled(context, value);
    final scaleFactor = widget.size / 54;
    final baseSize = s(widget.size);
    final iconSize = baseSize * 0.48;
    final enabled = widget.onPressed != null;
    final highlight = enabled && (_hovered || _pressed);
    final glowOpacity = enabled ? (highlight ? 0.7 : 0.35) : 0.0;
    final cursor =
        enabled ? SystemMouseCursors.click : SystemMouseCursors.basic;
    final baseColor = enabled
        ? ObsidianPalette.gold
        : ObsidianPalette.textMuted.withOpacity(0.28);
    final idleFill = enabled
        ? ObsidianPalette.obsidianElevated
        : ObsidianPalette.obsidianElevated.withOpacity(0.6);
    final idleIcon = enabled
        ? ObsidianPalette.gold
        : ObsidianPalette.textMuted.withOpacity(0.75);

    return MouseRegion(
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled ? (_) => _setHovered(false) : null,
      cursor: cursor,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        child: ClipPath(
          clipper: const _OctagonClipper(cutFraction: 0.3),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: glowOpacity),
            duration: _transition,
            curve: Curves.easeOut,
            builder: (context, animatedGlow, _) {
              return Container(
                width: baseSize,
                height: baseSize,
                decoration: BoxDecoration(
                  color: baseColor,
                  boxShadow: [
                    if (animatedGlow > 0)
                      BoxShadow(
                        color:
                            ObsidianPalette.gold.withOpacity(animatedGlow),
                        blurRadius: s(14 * scaleFactor),
                      ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(s(1.5 * scaleFactor)),
                  child: ClipPath(
                    clipper: const _OctagonClipper(cutFraction: 0.3),
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: highlight
                            ? ObsidianPalette.gold
                            : idleFill,
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
                                  : idleIcon,
                            ),
                            duration: _transition,
                            curve: Curves.easeOut,
                            builder: (context, animatedIconColor, ___) {
                              return Icon(
                                widget.icon,
                                color: animatedIconColor,
                                size: iconSize,
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
    final s = (double value) => _scaled(context, value);
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
          alignment: Alignment.center,
          constraints: BoxConstraints(minHeight: s(36)),
          padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(6)),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            boxShadow: [
              if (_hovered)
                BoxShadow(
                  color: ObsidianPalette.gold.withOpacity(0.35),
                  blurRadius: s(10),
                ),
            ],
          ),
          child: AnimatedDefaultTextStyle(
            duration: _transition,
            curve: Curves.easeOut,
            style: GoogleFonts.rajdhani(
              fontSize: s(13),
              fontWeight: FontWeight.w600,
              letterSpacing: s(1.2),
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
    required this.onSeekPreview,
    required this.positionLabel,
    required this.durationLabel,
    required this.enabled,
  });

  final SliderThemeData sliderTheme;
  final double maxSeconds;
  final double positionSeconds;
  final double bufferedPositionSeconds;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final String positionLabel;
  final String durationLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final progressTheme = sliderTheme.copyWith(
      trackHeight: s(6),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(7)),
      thumbColor: Colors.white,
      overlayShape: RoundSliderOverlayShape(overlayRadius: s(18)),
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withOpacity(0.35),
    );
    return Padding(
      padding: EdgeInsets.only(top: s(2)),
      child: Row(
        children: [
          SizedBox(
            width: s(42),
            child: Text(
              positionLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                fontSize: s(13),
                letterSpacing: s(1.1),
                color: ObsidianPalette.textMuted,
              ),
            ),
          ),
          SizedBox(width: s(12)),
          Expanded(
            child: SizedBox(
              height: s(36),
              child: SliderTheme(
                data: progressTheme,
                child: Slider(
                  value: positionSeconds,
                  max: maxSeconds,
                  secondaryTrackValue: bufferedPositionSeconds,
                  onChanged: enabled
                      ? (value) => onSeekPreview(Duration(seconds: value.toInt()))
                      : null,
                  onChangeEnd: enabled
                      ? (value) => onSeek(Duration(seconds: value.toInt()))
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(width: s(12)),
          SizedBox(
            width: s(42),
            child: Text(
              durationLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                fontSize: s(13),
                letterSpacing: s(1.1),
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
  const _TechTag({
    required this.label,
    this.highlight = false,
    this.outlineColor,
  });

  final String label;
  final bool highlight;
  final Color? outlineColor;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final borderColor = outlineColor ??
        (highlight
            ? ObsidianPalette.gold.withOpacity(0.6)
            : Colors.white.withOpacity(0.1));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(4), vertical: s(0.5)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: s(9.5),
          fontWeight: FontWeight.w600,
          letterSpacing: s(0.6),
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
    final s = (double value) => _scaled(context, value);
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
                letterSpacing: s(0.4),
              ),
            ),
          ),
          SizedBox(width: s(12)),
          trailing,
        ],
      ),
    );
  }
}

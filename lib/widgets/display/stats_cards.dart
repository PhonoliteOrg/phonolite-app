import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';
import '../ui/reload_icon.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/models.dart';
import 'artist_row_tile.dart';
import 'genre_text.dart';
import '../layout/library_header.dart';
import '../layouts/obsidian_scale.dart';
import '../layouts/playback_content_inset.dart';
import '../modals/modal_action_button.dart';
import '../modals/obsidian_dialog.dart';
import '../ui/obsidian_glass_surface.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import '../ui/button_haptics.dart';

double _scaled(BuildContext context, double value) =>
    value * ObsidianScale.of(context);

String _listeningDuration(int milliseconds) {
  if (milliseconds <= 0) return '0m';
  if (milliseconds < 1000) return '<1s';
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  if (seconds >= 3600) {
    return '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m ${seconds % 60}s';
  }
  return '${seconds ~/ 60}m ${seconds % 60}s';
}

class StatsCards extends StatelessWidget {
  const StatsCards({
    super.key,
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
    this.onRefresh,
    this.historyStatus,
    this.artistCoverUrl,
    this.artistImageHeaders = const {},
    this.onArtistTap,
    this.onTrackTap,
  });

  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback? onRefresh;
  final Widget? historyStatus;
  final String? Function(StatsItem)? artistCoverUrl;
  final Map<String, String> artistImageHeaders;
  final ValueChanged<StatsItem>? onArtistTap;
  final ValueChanged<StatsTrack>? onTrackTap;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16 + PlaybackContentInset.topOf(context),
        20,
        s(20) + PlaybackContentInset.bottomOf(context),
      ),
      // These cards and selectors occupy disjoint rectangles. Their matching
      // blur can sample the backdrop once instead of once for every panel.
      child: BackdropGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsHeader(
              stats: stats,
              onYearChanged: onYearChanged,
              onMonthChanged: onMonthChanged,
              onRefresh: onRefresh,
              historyStatus: historyStatus,
            ),
            SizedBox(height: s(20)),
            _KpiGrid(stats: stats),
            if (stats.topTracks.isEmpty &&
                stats.totalMinutes == 0 &&
                stats.totalListeningMs == 0) ...[
              SizedBox(height: s(12)),
              _emptyText('No listening in this period yet.'),
            ],
            SizedBox(height: s(28)),
            _AnalysisSection(
              stats: stats,
              artistCoverUrl: artistCoverUrl,
              artistImageHeaders: artistImageHeaders,
              onArtistTap: onArtistTap,
            ),
            SizedBox(height: s(28)),
            _TopTracksSection(tracks: stats.topTracks, onTrackTap: onTrackTap),
          ],
        ),
      ),
    );
  }
}

/// Describes which listening history is visible and whether account sync is
/// available. All listening totals remain visible when collection is off.
class StatsHistoryStatus extends StatelessWidget {
  const StatsHistoryStatus({
    super.key,
    required this.collectionEnabled,
    required this.hasAccount,
    required this.connected,
    required this.serverEnabled,
    this.syncing = false,
    this.lastSyncedAt,
    this.message,
    this.onImport,
  });

  final bool collectionEnabled;
  final bool hasAccount;
  final bool connected;
  final bool serverEnabled;
  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? message;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final iconSize = MediaQuery.sizeOf(context).width < 640 ? 22.0 : 26.0;
    final statusIcon = !collectionEnabled
        ? PhonoliteIcons.circlePause
        : !hasAccount
        ? PhonoliteIcons.database
        : !connected || !serverEnabled
        ? PhonoliteIcons.cloudOff
        : syncing
        ? PhonoliteIcons.cloudSync
        : PhonoliteIcons.cloudCheck;
    return Tooltip(
      message: 'Listening history status',
      child: ObsidianHudIconButton(
        icon: statusIcon,
        size: iconSize,
        onPressed: () => _showStatus(context),
      ),
    );
  }

  Future<void> _showStatus(BuildContext context) async {
    final importRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ObsidianAlertDialog(
        title: const Text('Listening history'),
        scrollable: true,
        content: DefaultTextStyle.merge(
          style: const TextStyle(color: ObsidianPalette.textMuted, height: 1.4),
          child: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_statusText()),
                if (hasAccount && lastSyncedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(_lastSyncText(dialogContext)),
                ],
                if (onImport != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Listening recorded before signing in stays on this device until you add it to your account.',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ModalActionButton(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          if (onImport != null)
            ModalActionButton(
              label: 'Add local history',
              icon: PhonoliteIcons.cloud,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
        ],
      ),
    );
    if (importRequested == true && context.mounted) {
      onImport?.call();
    }
  }

  String _statusText() {
    if (!collectionEnabled) {
      return 'Collection is off on this device. New listening and uploads are stopped; existing history is kept.';
    }
    final providedMessage = message?.trim();
    if (providedMessage != null && providedMessage.isNotEmpty) {
      return providedMessage;
    }
    if (!hasAccount) return 'Listening is saved on this device, even offline.';
    if (!serverEnabled) {
      return 'Server sync is disabled. Listening is saved on this device.';
    }
    if (!connected) {
      return 'Offline. Listening is saved on this device and will sync when connected.';
    }
    if (syncing) return 'Syncing listening history across your apps…';
    return 'Listening is saved on this device and synced across your apps.';
  }

  String _lastSyncText(BuildContext context) {
    final local = lastSyncedAt!.toLocal();
    final labels = MaterialLocalizations.of(context);
    final date = labels.formatShortDate(local);
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return 'Last synced $date at $time.';
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
    this.onRefresh,
    this.historyStatus,
  });

  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback? onRefresh;
  final Widget? historyStatus;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final isCompact = MediaQuery.of(context).size.width < 520;
    final compactHeaderActions = MediaQuery.sizeOf(context).width < 640;
    final selectorScale = isCompact ? 1.3 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibraryHeader(
          title: 'LISTENING STATISTICS',
          moduleCount: 0,
          shrinkTitleToFit: true,
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: compactHeaderActions ? 4 : 10,
            runSpacing: compactHeaderActions ? 4 : 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (historyStatus != null) historyStatus!,
              if (onRefresh != null) ...[
                Tooltip(
                  message: 'Refresh listening history',
                  child: Semantics(
                    button: true,
                    label: 'Refresh listening history',
                    child: ObsidianHudIconButton(
                      iconWidget: const ReloadIcon(),
                      onPressed: onRefresh,
                      size: compactHeaderActions ? 22 : 26,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (isCompact)
          Row(
            children: [
              Expanded(
                child: _TemporalSelector(
                  label: _monthLabel(stats.month),
                  width: double.infinity,
                  scale: selectorScale,
                  onPrev: () => onMonthChanged(_stepMonth(stats.month, -1)),
                  onNext: () => onMonthChanged(_stepMonth(stats.month, 1)),
                ),
              ),
              SizedBox(width: s(12)),
              Expanded(
                child: _TemporalSelector(
                  label: stats.year.toString(),
                  width: double.infinity,
                  scale: selectorScale,
                  onPrev: () => onYearChanged(stats.year - 1),
                  onNext: () => onYearChanged(stats.year + 1),
                ),
              ),
            ],
          )
        else
          Wrap(
            spacing: s(20),
            runSpacing: s(12),
            children: [
              _TemporalSelector(
                label: _monthLabel(stats.month),
                width: s(180),
                scale: selectorScale,
                onPrev: () => onMonthChanged(_stepMonth(stats.month, -1)),
                onNext: () => onMonthChanged(_stepMonth(stats.month, 1)),
              ),
              _TemporalSelector(
                label: stats.year.toString(),
                width: s(140),
                scale: selectorScale,
                onPrev: () => onYearChanged(stats.year - 1),
                onNext: () => onYearChanged(stats.year + 1),
              ),
            ],
          ),
      ],
    );
  }

  String _monthLabel(int? month) {
    if (month == null) {
      return 'ALL MONTHS';
    }
    const names = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final idx = (month - 1).clamp(0, names.length - 1);
    return names[idx];
  }

  int? _stepMonth(int? current, int delta) {
    const values = [null, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    final idx = values.indexOf(current);
    final next = (idx + delta).clamp(0, values.length - 1);
    return values[next];
  }
}

class _TemporalSelector extends StatelessWidget {
  const _TemporalSelector({
    required this.label,
    required this.width,
    required this.onPrev,
    required this.onNext,
    this.scale = 1.0,
  });

  final String label;
  final double width;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value * scale);
    final iconSize = s(20);
    return ObsidianGlassSurface(
      grouped: true,
      backgroundColor: ObsidianPalette.obsidianElevated.withValues(alpha: 0.56),
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(8)),
        child: Row(
          children: [
            _SelectorIconButton(
              icon: PhonoliteIcons.chevronLeft,
              onTap: onPrev,
              size: iconSize,
            ),
            SizedBox(width: s(6)),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.rajdhani(
                      fontSize: s(14),
                      fontWeight: FontWeight.w700,
                      letterSpacing: s(1.2),
                      color: ObsidianPalette.gold,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: s(6)),
            _SelectorIconButton(
              icon: PhonoliteIcons.chevronRight,
              onTap: onNext,
              size: iconSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorIconButton extends StatelessWidget {
  const _SelectorIconButton({
    required this.icon,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        onTap: withButtonHaptic(onTap),
        behavior: HitTestBehavior.opaque,
        child: Icon(icon, color: ObsidianPalette.gold, size: size),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.stats});

  final StatsResponse stats;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final values = <(String, String)>[
      ('TOTAL PLAYTIME', _listeningTime()),
      ('TOTAL PLAYS', '${stats.totalPlays}'),
      (
        'TRACKS LISTENED',
        _distinctCount(stats.uniqueTracks, stats.topTracks.length),
      ),
      (
        'ARTISTS LISTENED',
        _distinctCount(stats.uniqueArtists, stats.topArtists.length),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final columns = isCompact ? 2 : 4;
        final gap = s(isCompact ? 12 : 16);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: _KpiCard(
                  label: value.$1,
                  value: value.$2,
                  compact: isCompact,
                  tooltip: value.$1 == 'TOTAL PLAYS'
                      ? 'A play counts after 30 seconds, or half of a shorter track. '
                            'Brief listens still contribute to listening time and tracks listened.'
                      : value.$1 == 'TRACKS LISTENED'
                      ? 'Distinct tracks with any audio played, including brief listens.'
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  String _listeningTime() {
    final milliseconds = stats.totalListeningMs;
    if (milliseconds <= 0) return '${stats.totalMinutes}m';
    return _listeningDuration(milliseconds);
  }

  // Older server responses expose only rankings. The plus sign makes their
  // lower bound explicit until complete period counts become available.
  String _distinctCount(int total, int rankingSize) =>
      total > 0 || rankingSize == 0 ? '$total' : '$rankingSize+';
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.compact = false,
    this.tooltip,
  });

  final String label;
  final String value;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final padding = compact ? EdgeInsets.all(s(12)) : EdgeInsets.all(s(18));
    final labelSize = compact ? s(10) : s(12);
    final valueSize = compact ? s(32) : s(48);
    final surface = ObsidianGlassSurface(
      grouped: true,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                letterSpacing: s(1.4),
                color: ObsidianPalette.textMuted,
              ),
            ),
            SizedBox(height: s(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.rajdhani(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w700,
                  color: ObsidianPalette.gold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null
        ? surface
        : Tooltip(message: tooltip!, child: surface);
  }
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({
    required this.stats,
    required this.artistCoverUrl,
    required this.artistImageHeaders,
    required this.onArtistTap,
  });

  final StatsResponse stats;
  final String? Function(StatsItem)? artistCoverUrl;
  final Map<String, String> artistImageHeaders;
  final ValueChanged<StatsItem>? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final left = _TopGenresSection(
      genres: stats.topGenres,
      totalListeningMs: stats.totalListeningMs > 0
          ? stats.totalListeningMs
          : stats.totalMinutes * 60000,
      otherListeningMs: stats.otherGenreListeningMs,
      unclassifiedListeningMs: stats.unclassifiedListeningMs,
      fillHeight: isWide,
    );
    final right = _TopArtistsSection(
      artists: stats.topArtists,
      coverUrl: artistCoverUrl,
      headers: artistImageHeaders,
      onArtistTap: onArtistTap,
    );
    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            SizedBox(width: s(20)),
            Expanded(child: right),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        SizedBox(height: s(24)),
        right,
      ],
    );
  }
}

class _TopGenresSection extends StatelessWidget {
  const _TopGenresSection({
    required this.genres,
    required this.totalListeningMs,
    required this.otherListeningMs,
    required this.unclassifiedListeningMs,
    this.fillHeight = false,
  });

  final List<StatsItem> genres;
  final int totalListeningMs;
  final int otherListeningMs;
  final int unclassifiedListeningMs;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _ModuleShell(
      title: 'TOP GENRES',
      expandChild: fillHeight,
      tooltip:
          'Listening time is shared evenly between a song’s genres. '
          'Other genres includes those outside the top five. '
          'Unclassified means genre metadata is unavailable. '
          'Displayed durations are rounded down to whole seconds.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (genres.isEmpty &&
              otherListeningMs == 0 &&
              unclassifiedListeningMs == 0)
            _emptyText('No genres yet.')
          else
            for (final genre in genres)
              _GenreBar(
                label: genre.name,
                listeningMs: genre.listeningMs,
                totalListeningMs: totalListeningMs,
              ),
          if (otherListeningMs > 0)
            _GenreBar(
              label: 'Other genres',
              listeningMs: otherListeningMs,
              totalListeningMs: totalListeningMs,
            ),
          if (unclassifiedListeningMs > 0)
            _GenreBar(
              label: 'Unclassified',
              listeningMs: unclassifiedListeningMs,
              totalListeningMs: totalListeningMs,
            ),
        ],
      ),
    );
  }
}

class _GenreBar extends StatelessWidget {
  const _GenreBar({
    required this.label,
    required this.listeningMs,
    required this.totalListeningMs,
  });

  final String label;
  final int listeningMs;
  final int totalListeningMs;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final percent = totalListeningMs <= 0
        ? 0.0
        : listeningMs / totalListeningMs;
    final barPercent = percent.clamp(0.0, 1.0);
    final timeLabel = _listeningDuration(listeningMs);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s(10)),
      child: Row(
        children: [
          SizedBox(
            width: s(100),
            child: Text(
              genreDisplayLabel(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: s(1.0),
              ),
            ),
          ),
          SizedBox(width: s(12)),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: s(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(s(6)),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barPercent,
                  child: Container(
                    height: s(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ObsidianPalette.gold,
                          ObsidianPalette.gold.withOpacity(0.4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(s(6)),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: s(1),
                  child: Container(
                    width: s(2),
                    height: s(6),
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: s(12)),
          Text(
            timeLabel,
            style: GoogleFonts.rajdhani(
              fontSize: s(12),
              fontWeight: FontWeight.w700,
              color: ObsidianPalette.gold,
              letterSpacing: s(1.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopArtistsSection extends StatelessWidget {
  const _TopArtistsSection({
    required this.artists,
    required this.coverUrl,
    required this.headers,
    required this.onArtistTap,
  });

  final List<StatsItem> artists;
  final String? Function(StatsItem)? coverUrl;
  final Map<String, String> headers;
  final ValueChanged<StatsItem>? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final topArtists = artists.take(5).toList();
    return _ModuleShell(
      title: 'TOP ARTISTS',
      child: Column(
        children: [
          if (topArtists.isEmpty)
            _emptyText('No artists yet.')
          else
            for (var i = 0; i < topArtists.length; i++)
              ArtistRowTile(
                key: topArtists[i].id.trim().isEmpty
                    ? null
                    : ValueKey('stats-artist-${topArtists[i].id}'),
                onTap: onArtistTap == null || topArtists[i].id.trim().isEmpty
                    ? null
                    : () => onArtistTap!(topArtists[i]),
                artist: Artist(
                  id: topArtists[i].id,
                  name: topArtists[i].name,
                  albumCount: 0,
                ),
                coverUrl: coverUrl?.call(topArtists[i]),
                headers: headers,
                subtitle:
                    '${_listeningDuration(topArtists[i].listeningMs)} listened',
                trailing: SizedBox(
                  width: s(30),
                  child: Text(
                    '${i + 1}'.padLeft(2, '0'),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.rajdhani(
                      fontSize: s(18),
                      fontWeight: FontWeight.w700,
                      color: ObsidianPalette.gold,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _TopTracksSection extends StatelessWidget {
  const _TopTracksSection({required this.tracks, required this.onTrackTap});

  final List<StatsTrack> tracks;
  final ValueChanged<StatsTrack>? onTrackTap;

  @override
  Widget build(BuildContext context) {
    final topTracks = tracks.take(10).toList();
    return _ModuleShell(
      title: 'MOST PLAYED TRACKS',
      child: Column(
        children: [
          if (topTracks.isEmpty)
            _emptyText('No tracks yet.')
          else
            for (var i = 0; i < topTracks.length; i++)
              _TrackRow(
                key: topTracks[i].id.trim().isEmpty
                    ? null
                    : ValueKey('stats-track-${topTracks[i].id}'),
                onTap: onTrackTap == null || topTracks[i].id.trim().isEmpty
                    ? null
                    : () => onTrackTap!(topTracks[i]),
                rank: i + 1,
                title: topTracks[i].title,
                playCount: topTracks[i].plays,
              ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    super.key,
    required this.rank,
    required this.title,
    required this.playCount,
    this.onTap,
  });

  final int rank;
  final String title;
  final int playCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return ObsidianHoverRow(
      onTap: onTap,
      borderWidth: s(2),
      padding: EdgeInsets.symmetric(vertical: s(10), horizontal: s(12)),
      hoverColor: Colors.white.withOpacity(0.05),
      child: Row(
        children: [
          SizedBox(
            width: s(46),
            child: Text(
              rank.toString().padLeft(2, '0'),
              style: GoogleFonts.rajdhani(
                fontSize: s(22),
                fontWeight: FontWeight.w700,
                color: ObsidianPalette.gold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(letterSpacing: s(0.6)),
            ),
          ),
          Text(
            '${playCount} PLAYS',
            style: GoogleFonts.rajdhani(
              fontSize: s(12),
              fontWeight: FontWeight.w700,
              color: ObsidianPalette.gold,
              letterSpacing: s(1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleShell extends StatelessWidget {
  const _ModuleShell({
    required this.title,
    required this.child,
    this.tooltip,
    this.expandChild = false,
  });

  final String title;
  final Widget child;
  final String? tooltip;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return ObsidianGlassSurface(
      grouped: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(s(18), s(16), s(18), s(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: tooltip ?? '',
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.rajdhani(
                  fontSize: s(14),
                  fontWeight: FontWeight.w700,
                  letterSpacing: s(1.6),
                ),
              ),
            ),
            SizedBox(height: s(12)),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

Widget _emptyText(String text) {
  return Builder(
    builder: (context) {
      final s = (double value) => _scaled(context, value);
      return Padding(
        padding: EdgeInsets.symmetric(vertical: s(12)),
        child: Text(
          text,
          style: GoogleFonts.poppins(color: ObsidianPalette.textMuted),
        ),
      );
    },
  );
}

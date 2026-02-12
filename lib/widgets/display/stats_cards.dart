import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/chamfer_clipper.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

double _scaled(BuildContext context, double value) =>
    value * ObsidianScale.of(context);

class StatsCards extends StatelessWidget {
  const StatsCards({
    super.key,
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return SingleChildScrollView(
      padding: EdgeInsets.all(s(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatsHeader(
            stats: stats,
            onYearChanged: onYearChanged,
            onMonthChanged: onMonthChanged,
          ),
          SizedBox(height: s(20)),
          _KpiGrid(stats: stats),
          SizedBox(height: s(28)),
          _AnalysisSection(stats: stats),
          SizedBox(height: s(28)),
          _TopTracksSection(tracks: stats.topTracks),
        ],
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final isCompact = MediaQuery.of(context).size.width < 520;
    final selectorScale = isCompact ? 1.3 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 42),
            SizedBox(width: 20),
            Expanded(
              child: ObsidianSectionHeader(
                title: 'Listening Statistics',
              ),
            ),
          ],
        ),
        SizedBox(height: s(16)),
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
    return ClipPath(
      clipper: ChamferClipper(cutSize: s(15)),
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(8)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            _SelectorIconButton(
              icon: Icons.chevron_left_rounded,
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
              icon: Icons.chevron_right_rounded,
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
        onTap: onTap,
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
    final minutesLabel = '${stats.totalMinutes}m';
    final topArtists = stats.topArtists.length;
    final topTracks = stats.topTracks.length;
    final cards = [
      _KpiCard(label: 'TOTAL PLAYTIME', value: minutesLabel),
      _KpiCard(label: 'TOP ARTISTS', value: '$topArtists'),
      _KpiCard(label: 'TOP TRACKS', value: '$topTracks'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        if (isCompact) {
          final gap = s(12);
          return Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'TOTAL PLAYTIME',
                  value: minutesLabel,
                  compact: true,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _KpiCard(
                  label: 'TOP ARTISTS',
                  value: '$topArtists',
                  compact: true,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _KpiCard(
                  label: 'TOP TRACKS',
                  value: '$topTracks',
                  compact: true,
                ),
              ),
            ],
          );
        }
        return Wrap(
          spacing: s(16),
          runSpacing: s(16),
          children: cards,
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final padding = compact ? EdgeInsets.all(s(12)) : EdgeInsets.all(s(18));
    final labelSize = compact ? s(10) : s(12);
    final valueSize = compact ? s(32) : s(48);
    return ClipPath(
      clipper: ChamferClipper(cutSize: s(10)),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ObsidianPalette.gold.withOpacity(0.12),
              Colors.black.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
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
                  shadows: [
                    Shadow(
                      color: ObsidianPalette.gold.withOpacity(0.6),
                      blurRadius: s(10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({required this.stats});

  final StatsResponse stats;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final left = _TopGenresSection(genres: stats.topGenres);
    final right = _TopArtistsSection(artists: stats.topArtists);
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          SizedBox(width: s(20)),
          Expanded(child: right),
        ],
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
  const _TopGenresSection({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return _ModuleShell(
      title: 'TOP GENRES',
      icon: Icons.pie_chart_rounded,
      child: Column(
        children: [
          if (genres.isEmpty)
            _emptyText('No genres yet.')
          else
            for (var i = 0; i < genres.length; i++)
              _GenreBar(
                label: genres[i],
                percent: _rankPercent(i, genres.length),
              ),
        ],
      ),
    );
  }

  double _rankPercent(int index, int total) {
    if (total <= 1) {
      return 0.9;
    }
    final max = 0.9;
    final min = 0.35;
    final t = index / (total - 1);
    return max - (max - min) * t;
  }
}

class _GenreBar extends StatelessWidget {
  const _GenreBar({required this.label, required this.percent});

  final String label;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final percentLabel = '${(percent * 100).round()}%';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s(10)),
      child: Row(
        children: [
          SizedBox(
            width: s(100),
            child: Text(
              label.toUpperCase(),
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
                  widthFactor: percent,
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
                      boxShadow: [
                        BoxShadow(
                          color: ObsidianPalette.gold.withOpacity(0.5),
                          blurRadius: s(10),
                        ),
                      ],
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
            percentLabel,
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
  const _TopArtistsSection({required this.artists});

  final List<String> artists;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return _ModuleShell(
      title: 'TOP ARTISTS',
      icon: Icons.groups_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final columns = isCompact ? 2 : 3;
          final aspect = isCompact ? 1.0 : 0.9;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: artists.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: s(12),
              mainAxisSpacing: s(16),
              childAspectRatio: aspect,
            ),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return _ArtistCard(
                artist: artist,
                rank: index + 1,
              );
            },
          );
        },
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist, required this.rank});

  final String artist;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    final initials = artist.isEmpty ? '?' : artist.characters.first;
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: s(80),
              height: s(80),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              alignment: Alignment.center,
              child: Text(
                initials.toUpperCase(),
                style: GoogleFonts.rajdhani(
                  fontSize: s(24),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: ClipPath(
                clipper: ChamferClipper(cutSize: s(6)),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: s(8), vertical: s(4)),
                  color: ObsidianPalette.gold.withOpacity(0.2),
                  child: Text(
                    '$rank',
                    style: GoogleFonts.rajdhani(
                      fontSize: s(12),
                      fontWeight: FontWeight.w700,
                      color: ObsidianPalette.gold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: s(10)),
        Text(
          artist,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                letterSpacing: s(0.8),
              ),
        ),
      ],
    );
  }
}

class _TopTracksSection extends StatelessWidget {
  const _TopTracksSection({required this.tracks});

  final List<String> tracks;

  @override
  Widget build(BuildContext context) {
    return _ModuleShell(
      title: 'MOST PLAYED TRACKS',
      icon: Icons.equalizer_rounded,
      child: Column(
        children: [
          if (tracks.isEmpty)
            _emptyText('No tracks yet.')
          else
            for (var i = 0; i < tracks.length; i++)
              _TrackRow(
                rank: i + 1,
                title: tracks[i],
                playCount: _playCountForRank(i),
              ),
        ],
      ),
    );
  }

  int _playCountForRank(int index) {
    return 140 - index * 9;
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.rank,
    required this.title,
    required this.playCount,
  });

  final int rank;
  final String title;
  final int playCount;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return ObsidianHoverRow(
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    letterSpacing: s(0.6),
                  ),
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
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = (double value) => _scaled(context, value);
    return ObsidianChamferPanel(
      cut: s(12),
      padding: EdgeInsets.fromLTRB(s(18), s(16), s(18), s(18)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
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
              SizedBox(width: s(8)),
              Icon(icon, size: s(18), color: ObsidianPalette.gold),
            ],
          ),
          SizedBox(height: s(12)),
          child,
        ],
      ),
    );
  }
}

Widget _emptyText(String text) {
  return Builder(builder: (context) {
    final s = (double value) => _scaled(context, value);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s(12)),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: ObsidianPalette.textMuted,
        ),
      ),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/models.dart';
import '../ui/chamfer_clipper.dart';
import '../ui/obsidian_theme.dart';

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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatsHeader(
            stats: stats,
            onYearChanged: onYearChanged,
            onMonthChanged: onMonthChanged,
          ),
          const SizedBox(height: 20),
          _KpiGrid(stats: stats),
          const SizedBox(height: 28),
          _AnalysisSection(stats: stats),
          const SizedBox(height: 28),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SYSTEM STATISTICS',
          style: GoogleFonts.rajdhani(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            _TemporalSelector(
              label: _monthLabel(stats.month),
              width: 180,
              onPrev: () => onMonthChanged(_stepMonth(stats.month, -1)),
              onNext: () => onMonthChanged(_stepMonth(stats.month, 1)),
            ),
            _TemporalSelector(
              label: stats.year.toString(),
              width: 140,
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
  });

  final String label;
  final double width;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const ChamferClipper(cutSize: 15),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SelectorIconButton(
              icon: Icons.chevron_left_rounded,
              onTap: onPrev,
            ),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: ObsidianPalette.gold,
              ),
            ),
            _SelectorIconButton(
              icon: Icons.chevron_right_rounded,
              onTap: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorIconButton extends StatelessWidget {
  const _SelectorIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: ObsidianPalette.gold),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.stats});

  final StatsResponse stats;

  @override
  Widget build(BuildContext context) {
    final minutesLabel = '${stats.totalMinutes}m';
    final topArtists = stats.topArtists.length;
    final topTracks = stats.topTracks.length;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _KpiCard(label: 'TOTAL PLAYTIME', value: minutesLabel),
        _KpiCard(label: 'TOP ARTISTS', value: '$topArtists'),
        _KpiCard(label: 'TOP TRACKS', value: '$topTracks'),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const ChamferClipper(cutSize: 10),
      child: Container(
        padding: const EdgeInsets.all(18),
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
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: ObsidianPalette.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: GoogleFonts.rajdhani(
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: ObsidianPalette.gold,
                shadows: [
                  Shadow(
                    color: ObsidianPalette.gold.withOpacity(0.6),
                    blurRadius: 10,
                  ),
                ],
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
    final isWide = MediaQuery.of(context).size.width >= 900;
    final left = _TopGenresSection(genres: stats.topGenres);
    final right = _TopArtistsSection(artists: stats.topArtists);
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 20),
          Expanded(child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        const SizedBox(height: 24),
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
    final percentLabel = '${(percent * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percent,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ObsidianPalette.gold,
                          ObsidianPalette.gold.withOpacity(0.4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: ObsidianPalette.gold.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 1,
                  child: Container(
                    width: 2,
                    height: 6,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            percentLabel,
            style: GoogleFonts.rajdhani(
              fontWeight: FontWeight.w700,
              color: ObsidianPalette.gold,
              letterSpacing: 1.1,
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
    return _ModuleShell(
      title: 'TOP ARTISTS',
      icon: Icons.groups_rounded,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: artists.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.9,
        ),
        itemBuilder: (context, index) {
          final artist = artists[index];
          return _ArtistCard(
            artist: artist,
            rank: index + 1,
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
    final initials = artist.isEmpty ? '?' : artist.characters.first;
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 80,
              height: 80,
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
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: ClipPath(
                clipper: const ChamferClipper(cutSize: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: ObsidianPalette.gold.withOpacity(0.2),
                  child: Text(
                    '$rank',
                    style: GoogleFonts.rajdhani(
                      fontWeight: FontWeight.w700,
                      color: ObsidianPalette.gold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          artist,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                letterSpacing: 0.8,
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

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.rank,
    required this.title,
    required this.playCount,
  });

  final int rank;
  final String title;
  final int playCount;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: highlight ? Colors.white.withOpacity(0.05) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: highlight ? ObsidianPalette.gold : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                widget.rank.toString().padLeft(2, '0'),
                style: GoogleFonts.rajdhani(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ObsidianPalette.gold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      letterSpacing: 0.6,
                    ),
              ),
            ),
            Text(
              '${widget.playCount} PLAYS',
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w700,
                color: ObsidianPalette.gold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
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
    return ClipPath(
      clipper: const ChamferClipper(cutSize: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: ObsidianPalette.gold),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _emptyText(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        color: ObsidianPalette.textMuted,
      ),
    ),
  );
}

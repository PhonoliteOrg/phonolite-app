import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class StatsHeader extends StatelessWidget {
  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback? onRefresh;
  final Widget? historyStatus;

  const StatsHeader({
    super.key,
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
    this.historyStatus,
    this.onRefresh,
  });

  String _monthLabel(int? month) {
    if (month == null) {
      return 'ALL MONTHS';
    }

    const names = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final idx = (month - 1).clamp(0, names.length - 1);

    return names[idx];
  }

  int? _stepMonth(int? current, int delta) {
    const values = [null, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    final idx = values.indexOf(current);
    final next = (idx + delta).clamp(0, values.length - 1);

    return values[next];
  }

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final isCompact = MediaQuery.of(context).size.width < 520;
    final actions = PageToolbarActionLayout.of(context);
    final selectorScale = isCompact ? 1.3 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibraryHeader(
          title: 'LISTENING STATISTICS',
          shrinkTitleToFit: true,
          trailing: PageToolbarActions(
            spacing: actions.spacing,
            runSpacing: actions.runSpacing,
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
                      size: actions.iconSize,
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
}

class _TemporalSelector extends StatelessWidget {
  final String label;
  final double width;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final double scale;

  const _TemporalSelector({
    required this.label,
    required this.width,
    required this.onPrev,
    required this.onNext,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value * scale);

    final iconSize = s(20);

    return ObsidianGlassSurface(
      grouped: true,
      backgroundColor: ObsidianPalette.obsidianElevated.withValues(alpha: 0.56),
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(8)),
        child: Row(
          children: [
            _SelectorIconButton(icon: PhonoliteIcons.chevronLeft, onTap: onPrev, size: iconSize),
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
            _SelectorIconButton(icon: PhonoliteIcons.chevronRight, onTap: onNext, size: iconSize),
          ],
        ),
      ),
    );
  }
}

class _SelectorIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _SelectorIconButton({required this.icon, required this.onTap, required this.size});

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

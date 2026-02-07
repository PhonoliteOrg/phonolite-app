import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/stats_cards.dart';
import '../widgets/layouts/app_scope.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (controller.stats == null) {
      controller.loadStats(month: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder(
      stream: controller.statsStream,
      initialData: controller.stats,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const EmptyState(
            title: 'No stats',
            message: 'Listening stats will appear once enabled on the server.',
          );
        }
        return StatsCards(
          stats: stats,
          onYearChanged: (year) => controller.loadStats(year: year, month: stats.month),
          onMonthChanged: (month) => controller.loadStats(year: stats.year, month: month),
        );
      },
    );
  }
}

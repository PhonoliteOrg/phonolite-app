import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/stats_cards.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/tech_button.dart';
import 'login_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _requestedServerLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (controller.authState.isAuthorized && controller.stats == null) {
      _requestedServerLoad = true;
      controller.loadStats(month: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final authState = authSnapshot.data ?? controller.authState;
        if (!authState.isAuthorized) {
          _requestedServerLoad = false;
          return _OfflineStats(
            onConnect: () =>
                Navigator.of(context).push(LoginPage.route(controller)),
          );
        }
        return _buildServerStats(controller);
      },
    );
  }

  Widget _buildServerStats(AppController controller) {
    if (!_requestedServerLoad && controller.stats == null) {
      _requestedServerLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.authState.isAuthorized) {
          controller.loadStats(month: null);
        }
      });
    }
    return StreamBuilder(
      stream: controller.statsStream,
      initialData: controller.stats,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const EmptyStateText(
            title: 'No stats',
            message: 'Listening stats will appear once enabled on the server.',
          );
        }
        return StatsCards(
          stats: stats,
          onYearChanged: (year) =>
              controller.loadStats(year: year, month: stats.month),
          onMonthChanged: (month) =>
              controller.loadStats(year: stats.year, month: month),
          onRefresh: () =>
              controller.loadStats(year: stats.year, month: stats.month),
        );
      },
    );
  }
}

class _OfflineStats extends StatelessWidget {
  const _OfflineStats({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stats need a server connection.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: 0.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TechButton(
              label: 'Connect / Log in',
              icon: Icons.login_rounded,
              onTap: onConnect,
              density: TechButtonDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

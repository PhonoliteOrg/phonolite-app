import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/listening_stats/stats_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_cards.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_header.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';

class StatsPage extends BasePage {
  final ValueChanged<StatsItem>? onArtistTap;
  final ValueChanged<StatsTrack>? onTrackTap;

  const StatsPage({super.key, this.onArtistTap, this.onTrackTap});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends BasePageState<StatsPage> {
  late final StatsController _feature = bindController(StatsController(AppScope.of(context)));

  @override
  EdgeInsetsGeometry get navbarPadding => EdgeInsets.only(bottom: statsScaled(context, 20));

  Future<void> _importLocalHistory(AppController controller) async {
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Add local listening history?',
      message:
          'Add listening recorded on this device before signing in to your current account? '
          'It will sync to the server and appear on your other apps.',
      confirmLabel: 'Add history',
      confirmVariant: TechButtonVariant.standard,
      actionChrome: TechButtonChrome.borderless,
    );

    if (!confirmed || !mounted) {
      return;
    }

    await _feature.importLocalHistory();
  }

  Widget _statsContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AsyncSnapshot<StatsResponse?> snapshot,
    required AuthState auth,
    required bool collectionEnabled,
  }) {
    final stats = snapshot.data ?? _feature.emptyStats();

    return BackdropGroup(
      child: assemble(
        context,
        navbar: StatsHeader(
          stats: stats,
          onYearChanged: (year) => controller.loadStats(year: year, month: stats.month),
          onMonthChanged: (month) => controller.loadStats(year: stats.year, month: month),
          onRefresh: () => controller.loadStats(year: stats.year, month: stats.month),
          historyStatus: StatsHistoryStatus(
            collectionEnabled: collectionEnabled,
            hasAccount: auth.hasSession,
            connected: auth.isAuthorized,
            serverEnabled: controller.statsServerCollectionEnabled,
            syncing: controller.statsSyncing,
            lastSyncedAt: controller.statsLastSyncedAt,
            message: controller.statsSyncMessage,
            onImport: collectionEnabled && controller.canImportLocalStats
                ? () => _importLocalHistory(controller)
                : null,
          ),
        ),
        body: PageBody.scroll(
          padding: EdgeInsets.fromLTRB(20, 16, 20, statsScaled(context, 20)),
          child: StatsCardsContent(
            stats: stats,
            onArtistTap: widget.onArtistTap,
            onTrackTap: widget.onTrackTap,
            artistCoverUrl: (artist) => _feature.artistCoverUrl(controller, auth, artist),
            artistImageHeaders: auth.isAuthorized ? controller.artworkHeaders : const {},
          ),
        ),
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final auth = authSnapshot.data ?? controller.authState;

        return StreamBuilder<bool>(
          stream: controller.statsCollectionEnabledStream,
          initialData: controller.statsCollectionEnabled,
          builder: (context, collectionSnapshot) {
            final collectionEnabled = collectionSnapshot.data ?? controller.statsCollectionEnabled;

            return StreamBuilder<StatsResponse?>(
              stream: controller.statsStream,
              initialData: controller.stats,
              builder: (context, snapshot) => _statsContent(
                context,
                assemble,
                controller,
                snapshot: snapshot,
                auth: auth,
                collectionEnabled: collectionEnabled,
              ),
            );
          },
        );
      },
    );
  }
}

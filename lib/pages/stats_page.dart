import 'dart:async';

import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/app_log.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../entities/offline_download_manager.dart';
import '../widgets/display/stats_cards.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/ui/tech_button.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.onArtistTap, this.onTrackTap});

  final ValueChanged<StatsItem>? onArtistTap;
  final ValueChanged<StatsTrack>? onTrackTap;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  AppController? _loadedController;
  StreamSubscription<List<Artist>>? _artistSubscription;
  StreamSubscription<OfflineLibrarySnapshot>? _offlineSubscription;
  Map<String, Artist> _artists = const {};
  OfflineLibrarySnapshot? _localArtworkSnapshot;
  String? _localArtworkScope;
  Map<String, String> _localArtistCovers = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (identical(_loadedController, controller)) return;
    _artistSubscription?.cancel();
    _offlineSubscription?.cancel();
    _loadedController = controller;
    _artists = {for (final artist in controller.artists) artist.id: artist};
    _localArtworkSnapshot = null;
    _artistSubscription = controller.artistsStream.listen((artists) {
      if (!mounted || !identical(_loadedController, controller)) return;
      setState(() {
        _artists = {for (final artist in artists) artist.id: artist};
      });
    });
    _offlineSubscription = controller.offlineLibrarySnapshotStream.listen((_) {
      if (!mounted || !identical(_loadedController, controller)) return;
      setState(() => _localArtworkSnapshot = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_loadedController, controller)) {
        controller.loadStats(month: null);
      }
    });
  }

  @override
  void dispose() {
    _artistSubscription?.cancel();
    _offlineSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            final collectionEnabled =
                collectionSnapshot.data ?? controller.statsCollectionEnabled;
            return StreamBuilder<StatsResponse?>(
              stream: controller.statsStream,
              initialData: controller.stats,
              builder: (context, snapshot) {
                final stats = snapshot.data ?? _emptyStats();
                return StatsCards(
                  stats: stats,
                  onArtistTap: widget.onArtistTap,
                  onTrackTap: widget.onTrackTap,
                  artistCoverUrl: (artist) =>
                      _artistCoverUrl(controller, auth, artist),
                  artistImageHeaders: auth.isAuthorized
                      ? controller.artworkHeaders
                      : const {},
                  onYearChanged: (year) =>
                      controller.loadStats(year: year, month: stats.month),
                  onMonthChanged: (month) =>
                      controller.loadStats(year: stats.year, month: month),
                  onRefresh: () => controller.loadStats(
                    year: stats.year,
                    month: stats.month,
                  ),
                  historyStatus: StatsHistoryStatus(
                    collectionEnabled: collectionEnabled,
                    hasAccount: auth.hasSession,
                    connected: auth.isAuthorized,
                    serverEnabled: controller.statsServerCollectionEnabled,
                    syncing: controller.statsSyncing,
                    pendingCount: controller.pendingStatsCount,
                    lastSyncedAt: controller.statsLastSyncedAt,
                    message: controller.statsSyncMessage,
                    onImport:
                        collectionEnabled && controller.canImportLocalStats
                        ? () => _importLocalHistory(controller)
                        : null,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String? _artistCoverUrl(
    AppController controller,
    AuthState auth,
    StatsItem artist,
  ) {
    final snapshot = controller.offlineLibrarySnapshot;
    final server = controller.connection.baseUrl;
    final scope = auth.hasSession ? server : '';
    if (!identical(_localArtworkSnapshot, snapshot) ||
        _localArtworkScope != scope) {
      final covers = <String, String>{};
      for (final track in snapshot.tracks) {
        // Download groups may contain copies from different servers. Keep
        // account artwork within the current server's catalog.
        if (auth.hasSession && track.serverBaseUrl != server) continue;
        final path = track.artistArtPath?.trim();
        if (path == null || path.isEmpty) continue;
        for (final id in [track.artistId, track.offlineArtist?.id]) {
          if (id != null && id.isNotEmpty) covers.putIfAbsent(id, () => path);
        }
        if (track.artistId?.isNotEmpty != true && track.artist.isNotEmpty) {
          covers.putIfAbsent(track.artist, () => path);
        }
      }
      _localArtworkSnapshot = snapshot;
      _localArtworkScope = scope;
      _localArtistCovers = covers;
    }
    final local = _localArtistCovers[artist.id];
    if (local != null) return local;
    if (!auth.isAuthorized || artist.id.isEmpty) return null;
    final metadata = _artists[artist.id];
    final logoRef = metadata?.logoRef?.trim();
    if (metadata != null && (logoRef == null || logoRef.isEmpty)) return null;
    return controller.connection.buildArtistCoverUrl(
      artist.id,
      kind: 'logo',
      ref: logoRef,
    );
  }

  StatsResponse _emptyStats() => StatsResponse(
    year: DateTime.now().year,
    month: null,
    totalMinutes: 0,
    topArtists: [],
    topTracks: [],
    topGenres: [],
  );

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
    if (!confirmed || !mounted) return;
    try {
      await controller.importLocalListeningHistory();
    } catch (error) {
      AppLogger.warning('Could not add listening history: $error');
    }
  }
}

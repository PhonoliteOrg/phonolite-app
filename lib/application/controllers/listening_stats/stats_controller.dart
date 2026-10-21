import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class StatsController extends FeatureController {
  final AppController app;
  Map<String, Artist> _artists = const {};
  OfflineLibrarySnapshot? _localArtworkSnapshot;
  String? _localArtworkScope;
  Map<String, String> _localArtistCovers = const {};

  StatsController(this.app) {
    _artists = {for (final artist in app.artists) artist.id: artist};
  }

  Map<String, Artist> get artists => Map.unmodifiable(_artists);

  @override
  Future<void> initializeFeature() {
    listenTo(
      app.artistsStream,
      (values) => update(() {
        _artists = {for (final artist in values) artist.id: artist};
      }),
    );
    listenTo(app.offlineLibrarySnapshotStream, (_) => update(() => _localArtworkSnapshot = null));

    return app.loadStats(month: null);
  }

  Future<void> importLocalHistory() async {
    try {
      await app.importLocalListeningHistory();
    } catch (error) {
      AppLogger.warning('Could not add listening history: $error');
    }
  }

  String? artistCoverUrl(AppController controller, AuthState auth, StatsItem artist) {
    final snapshot = controller.offlineLibrarySnapshot;
    final server = controller.connection.baseUrl;
    final scope = auth.hasSession ? server : '';

    if (!identical(_localArtworkSnapshot, snapshot) || _localArtworkScope != scope) {
      final covers = <String, String>{};

      for (final track in snapshot.tracks) {
        // Download groups may contain copies from different servers. Keep
        // account artwork within the current server's catalog.
        if (auth.hasSession && track.serverBaseUrl != server) {
          continue;
        }

        final path = track.artistArtPath?.trim();

        if (path == null || path.isEmpty) {
          continue;
        }

        for (final id in [track.artistId, track.offlineArtist?.id]) {
          if (id != null && id.isNotEmpty) {
            covers.putIfAbsent(id, () => path);
          }
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
    if (local != null) {
      return local;
    }

    if (!auth.isAuthorized || artist.id.isEmpty) {
      return null;
    }

    final metadata = _artists[artist.id];
    final logoRef = metadata?.logoRef?.trim();

    if (metadata != null && (logoRef == null || logoRef.isEmpty)) {
      return null;
    }

    return controller.connection.buildArtistCoverUrl(artist.id, kind: 'logo', ref: logoRef);
  }

  StatsResponse emptyStats() => StatsResponse(
    year: DateTime.now().year,
    month: null,
    totalMinutes: 0,
    topArtists: [],
    topTracks: [],
    topGenres: [],
  );
}

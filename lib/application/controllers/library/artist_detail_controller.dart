import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/data/models/downloads/artist_download_summary.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';

export 'package:phonolite_app/data/models/downloads/artist_download_summary.dart';

class ArtistDetailController extends FeatureController {
  final AppController app;
  late final _selection = ControllerSelection<String>(update);
  late Artist _artist;

  ArtistDetailController(this.app, Artist initialArtist) : _artist = initialArtist;

  Artist get artist => _artist;

  bool get albumSelectionMode => _selection.active;

  set albumSelectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedAlbumIds => _selection.keys();

  @override
  Future<void> initializeFeature() {
    final releases = app.loadArtistReleases(_artist.id);
    final refresh = refreshArtist(app);

    listenTo(app.watchArtist(_artist.id), (value) => update(() => _artist = value));

    return Future.wait([releases, refresh]);
  }

  Future<void> removeAlbumDownloads(List<Album> albums, String label) async {
    await app.removeOfflineDownloads(
      downloadsForAlbums(app, albums),
      label: label,
      scope: OfflineDeletionScope.album(id: albums.length == 1 ? albums.single.id : null, label: label),
    );

    if (!isDisposed) {
      clearAlbumSelection();
    }
  }

  Set<String> removableAlbumIds(AppController controller, List<Album> albums) {
    return <String>{
      for (final album in albums)
        if (downloadsForAlbum(controller, album).isNotEmpty) albumSelectionKey(album),
    };
  }

  List<Album> selectedAlbums(List<Album> albums, Set<String> removableIds) {
    bool isSelectedAndRemovable(Album album) {
      final key = albumSelectionKey(album);

      return removableIds.contains(key) && selectedAlbumIds.contains(key);
    }

    return albums.where(isSelectedAndRemovable).toList(growable: false);
  }

  void toggleAlbumSelection(Album album) {
    final key = albumSelectionKey(album);

    _selection.toggle(key);
  }

  void selectAllAlbums(Set<String> albumIds) {
    _selection.replace(albumIds);
  }

  void deselectAllAlbums() {
    _selection.clear(activate: true);
  }

  void clearAlbumSelection() {
    _selection.clear();
  }

  String albumSelectionKey(Album album) => album.id;

  Set<String> removingAlbumIds(AppController controller, List<Album> albums) {
    return <String>{
      for (final album in albums)
        if (albumHasRemovingDownloads(controller, album)) albumSelectionKey(album),
    };
  }

  List<OfflineTrackDownload> downloadsForAlbums(AppController controller, List<Album> albums) {
    final downloadsByKey = <String, OfflineTrackDownload>{};

    for (final album in albums) {
      for (final download in downloadsForAlbum(controller, album)) {
        downloadsByKey[downloadSelectionKey(download)] = download;
      }
    }

    return downloadsByKey.values.toList(growable: false);
  }

  List<OfflineTrackDownload> downloadsForAlbum(AppController controller, Album album) {
    return controller.offlineDownloads
        .where(
          (download) =>
              controller.availableOfflineDownloadForTrack(download.track.id) != null &&
              downloadBelongsToAlbum(download, album),
        )
        .toList(growable: false);
  }

  bool albumHasRemovingDownloads(AppController controller, Album album) {
    return controller.offlineDownloads.any(
      (download) => download.status == OfflineDownloadStatus.removing && downloadBelongsToAlbum(download, album),
    );
  }

  bool downloadBelongsToAlbum(OfflineTrackDownload download, Album album) {
    final track = download.track;
    final trackAlbumId = track.albumId?.trim();

    if (trackAlbumId != null && trackAlbumId.isNotEmpty) {
      return trackAlbumId == album.id;
    }

    final trackAlbum = normalizedAlbumSelectionValue(track.album);
    final albumTitle = normalizedAlbumSelectionValue(album.title);

    if (trackAlbum.isEmpty || trackAlbum != albumTitle) {
      return false;
    }

    final trackArtistId = track.artistId?.trim();

    if (trackArtistId != null && trackArtistId.isNotEmpty) {
      return trackArtistId == album.artistId || trackArtistId == _artist.id;
    }

    final trackArtist = normalizedAlbumSelectionValue(track.artist);

    if (trackArtist.isEmpty) {
      return true;
    }

    final albumArtist = normalizedAlbumSelectionValue(album.artist.isEmpty ? _artist.name : album.artist);
    final artistName = normalizedAlbumSelectionValue(_artist.name);

    return trackArtist == albumArtist || trackArtist == artistName;
  }

  Future<void> refreshArtist(AppController controller) async {
    try {
      final updated = await controller.connection.fetchArtistById(_artist.id);

      if (isDisposed) {
        return;
      }

      update(() => _artist = updated);
    } catch (_) {}
  }

  String albumCoverUrl(AppController controller, Album album) {
    return controller.connection.buildAlbumCoverUrl(album.id);
  }

  String downloadSelectionKey(OfflineTrackDownload download) {
    final trackId = download.track.serverTrackId ?? download.track.id;

    return '${download.serverBaseUrl}\n$trackId\n${download.localTrackId ?? ''}';
  }

  String normalizedAlbumSelectionValue(String value) {
    return value.trim().toLowerCase();
  }

  static ArtistDownloadSummary summarizeDownloads(AppController controller, Artist artist, List<Album> albums) {
    final albumIds = albums.map((album) => album.id).toSet();
    final albumTitles = albums
        .map((album) => album.title.trim().toLowerCase())
        .where((title) => title.isNotEmpty)
        .toSet();
    final artistName = artist.name.trim().toLowerCase();
    final downloads = <String, OfflineTrackDownload>{};

    for (final download in controller.offlineDownloads) {
      final track = download.track;
      final albumId = track.albumId;
      final trackArtist = track.artist.trim().toLowerCase();
      final trackAlbum = track.album.trim().toLowerCase();
      final belongsToArtist =
          track.artistId == artist.id ||
          (trackArtist.isNotEmpty && trackArtist == artistName) ||
          (albumId != null && albumIds.contains(albumId)) ||
          (trackAlbum.isNotEmpty &&
              albumTitles.contains(trackAlbum) &&
              (trackArtist.isEmpty || trackArtist == artistName));

      if (!belongsToArtist) {
        continue;
      }

      final key = download.localTrackId ?? track.localId ?? track.serverTrackId ?? track.id;

      downloads[key] = download;
    }

    var downloaded = 0;
    var active = 0;
    var failed = 0;

    for (final download in downloads.values) {
      if (controller.availableOfflineDownloadForTrack(download.track.id) != null) {
        downloaded++;
      } else if (download.status == OfflineDownloadStatus.queued ||
          download.status == OfflineDownloadStatus.preparing ||
          download.status == OfflineDownloadStatus.downloading ||
          download.status == OfflineDownloadStatus.validating ||
          download.status == OfflineDownloadStatus.removing) {
        active++;
      } else if (download.status == OfflineDownloadStatus.failed) {
        failed++;
      }
    }

    var hasActiveArtistJob = false;

    for (final job in controller.offlineDownloadJobs) {
      final jobLabel = job.label?.trim().toLowerCase();
      final belongsToArtist =
          job.kind == 'artist' && (job.sourceId == artist.id || (job.sourceId == null && jobLabel == artistName));

      if (!belongsToArtist) {
        continue;
      }

      if (job.status == OfflineDownloadStatus.queued ||
          job.status == OfflineDownloadStatus.preparing ||
          job.status == OfflineDownloadStatus.downloading ||
          job.status == OfflineDownloadStatus.validating ||
          job.status == OfflineDownloadStatus.paused ||
          job.status == OfflineDownloadStatus.removing) {
        hasActiveArtistJob = true;
      } else if (job.status == OfflineDownloadStatus.failed || job.status == OfflineDownloadStatus.corrupt) {
        failed += job.failedCount > 0 ? job.failedCount : 1;
      }
    }

    final total = albums.fold<int>(0, (sum, album) => sum + album.trackCount);

    return ArtistDownloadSummary(
      total: total,
      downloaded: downloaded,
      active: active,
      failed: failed,
      hasActiveArtistJob: hasActiveArtistJob,
      hasDownloadScope: albums.isNotEmpty,
    );
  }
}

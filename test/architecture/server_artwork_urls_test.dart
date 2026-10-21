import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/api/artwork_urls.dart';

void main() {
  const baseUrl = 'https://saved.test/api/v1';
  final timestamp = DateTime.utc(2026);

  OfflineDownloadJob job(String kind, {String? sourceId = ' item/# '}) => OfflineDownloadJob(
    jobId: 'job',
    kind: kind,
    serverBaseUrl: ' $baseUrl ',
    status: OfflineDownloadStatus.queued,
    createdAt: timestamp,
    updatedAt: timestamp,
    sourceId: sourceId,
  );

  OfflineTrackDownload download(Track track) => OfflineTrackDownload(
    serverBaseUrl: ' $baseUrl ',
    track: track,
    status: OfflineDownloadStatus.queued,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  test('shared URL policy retains escaping and cache-reference semantics', () {
    expect(ServerArtworkUrls.albumCover(baseUrl, 'album/#'), '$baseUrl/library/albums/album%2F%23/cover');
    expect(
      ServerArtworkUrls.playlistCover(baseUrl, 'playlist/#', imageRef: ' ref/# '),
      '$baseUrl/library/playlists/playlist%2F%23/cover?v=ref%2F%23',
    );
    expect(
      ServerArtworkUrls.artistCover(baseUrl, 'artist/#', kind: 'logo', ref: ' ref/# '),
      '$baseUrl/library/artists/artist%2F%23/cover?kind=logo&v=%20ref%2F%23%20',
    );
  });

  test('download jobs retain their saved origin and subject-specific fallback', () {
    expect(CatalogController.downloadJobCoverUrl(job('artist')), '$baseUrl/library/artists/item%2F%23/cover?kind=logo');
    expect(CatalogController.downloadJobCoverUrl(job('album')), '$baseUrl/library/albums/item%2F%23/cover');
    expect(CatalogController.downloadJobCoverUrl(job('playlist')), isNull);
    expect(CatalogController.downloadJobCoverUrl(job('album', sourceId: ' ')), isNull);
  });

  test('download artwork prefers a local path and otherwise uses its saved origin', () {
    final track = Track(
      id: 'track',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      durationMs: 0,
      liked: false,
      inPlaylists: false,
      albumId: ' album/# ',
    );

    expect(CatalogController.downloadArtworkUrl(download(track)), '$baseUrl/library/albums/album%2F%23/cover');
    expect(
      CatalogController.downloadArtworkUrl(download(track.copyWith(albumArtPath: ' /local/cover.png '))),
      '/local/cover.png',
    );
    expect(CatalogController.downloadArtworkUrl(download(track.copyWith(albumId: null))), isNull);
  });
}

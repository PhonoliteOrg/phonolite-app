@Tags(['requires-server'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('offline library sqlite behavior', () {
    test('rolling job scheduler alternates runnable job groups', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_round_robin_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final requested = <String>[];
      final firstRequest = Completer<void>();
      final releaseFirst = Completer<void>();
      final fourthRequest = Completer<void>();
      addTearDown(() {
        if (!releaseFirst.isCompleted) {
          releaseFirst.complete();
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (!request.uri.pathSegments.contains('tracks')) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final trackId = request.uri.pathSegments.last;
        requested.add(trackId);
        if (!firstRequest.isCompleted) {
          firstRequest.complete();
          await releaseFirst.future;
        }
        if (requested.length >= 4 && !fourthRequest.isCompleted) {
          fourthRequest.complete();
        }
        try {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = 3;
          request.response.add(<int>[1, 2, 3]);
          await request.response.close();
        } catch (_) {}
      });
      addTearDown(subscription.cancel);
      addTearDown(server.close);
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final connection = ServerConnection(
        baseUrl: 'http://${server.address.address}:${server.port}/api',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      await manager.queueBatch(
        offlineTestDownloadManifest(
          batchId: 'batch-a',
          trackId: 'a-track-1',
          itemCount: 25,
          trackPrefix: 'a-track-',
        ),
        label: 'A',
      );
      await firstRequest.future.timeout(const Duration(seconds: 3));
      await manager.queueBatch(
        offlineTestDownloadManifest(
          batchId: 'batch-b',
          trackId: 'b-track-1',
          itemCount: 25,
          trackPrefix: 'b-track-',
        ),
        label: 'B',
      );

      releaseFirst.complete();
      await fourthRequest.future.timeout(const Duration(seconds: 5));

      expect(requested.take(4), <String>[
        'a-track-1',
        'b-track-1',
        'a-track-2',
        'b-track-2',
      ]);
    });

    test(
      'paused rolling job leaves queued rows blocked while another job runs',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_paused_job_blocks_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final requested = <String>[];
        final firstRequest = Completer<void>();
        final secondRequest = Completer<void>();
        final releaseFirst = Completer<void>();
        addTearDown(() {
          if (!releaseFirst.isCompleted) {
            releaseFirst.complete();
          }
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (!request.uri.pathSegments.contains('tracks')) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          final trackId = request.uri.pathSegments.last;
          requested.add(trackId);
          if (!firstRequest.isCompleted) {
            firstRequest.complete();
            await releaseFirst.future;
          } else if (!secondRequest.isCompleted) {
            secondRequest.complete();
          }
          try {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 3;
            request.response.add(<int>[1, 2, 3]);
            await request.response.close();
          } catch (_) {}
        });
        addTearDown(subscription.cancel);
        addTearDown(server.close);
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final connection = ServerConnection(
          baseUrl: 'http://${server.address.address}:${server.port}/api',
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        await manager.queueBatch(
          offlineTestDownloadManifest(
            batchId: 'batch-paused',
            trackId: 'paused-track-1',
            itemCount: 25,
            trackPrefix: 'paused-track-',
          ),
          label: 'Paused',
        );
        await firstRequest.future.timeout(const Duration(seconds: 3));
        await manager.queueBatch(
          offlineTestDownloadManifest(
            batchId: 'batch-next',
            trackId: 'next-track-1',
            itemCount: 25,
            trackPrefix: 'next-track-',
          ),
          label: 'Next',
        );

        await manager.pauseDownloadJob(
          manager.jobs.singleWhere((job) => job.jobId == 'batch-paused'),
        );
        releaseFirst.complete();
        await secondRequest.future.timeout(const Duration(seconds: 5));

        final pausedJob = manager.jobs.singleWhere(
          (job) => job.jobId == 'batch-paused',
        );
        final pausedJobDownloads = manager.downloads
            .where((download) => download.batchId == pausedJob.jobId)
            .toList(growable: false);
        expect(pausedJob.status, OfflineDownloadStatus.paused);
        expect(requested.take(2), <String>['paused-track-1', 'next-track-1']);
        expect(
          pausedJobDownloads
              .where(
                (download) => download.status == OfflineDownloadStatus.queued,
              )
              .length,
          greaterThan(0),
        );
        expect(
          pausedJobDownloads
              .where(
                (download) => download.status == OfflineDownloadStatus.paused,
              )
              .length,
          1,
        );
      },
    );

    test('manager downloads media on a worker isolate', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_worker_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final body = <int>[1, 2, 3, 4];
      String? authorization;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        if (request.uri.path == '/api/download/tracks/server-track-1') {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = body.length;
          request.response.add(body);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final completed = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloaded,
        ),
      );

      await manager.queueBatch(
        offlineTestDownloadManifest(
          batchId: 'batch-worker',
          trackId: 'server-track-1',
          byteLength: body.length,
        ),
        label: 'Worker Album',
      );

      final downloads = await completed.timeout(const Duration(seconds: 5));
      final downloaded = downloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      expect(authorization, 'Bearer token-1');
      expect(downloaded.filePath, isNotEmpty);
      expect(downloaded.bytesDownloaded, body.length);
      expect(downloaded.bytesTotal, body.length);
      expect(await File(downloaded.filePath!).readAsBytes(), body);
    });

    test(
      'manager redownloads a removed track without inheriting cancel state',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_redownload_cancel_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final body = <int>[9, 8, 7, 6];
        var downloadRequests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (request.uri.path == '/api/download/tracks/server-track-1') {
            downloadRequests += 1;
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        addTearDown(() => server.close(force: true));

        final connection = ServerConnection(
          baseUrl: 'http://127.0.0.1:${server.port}/api',
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        Future<OfflineTrackDownload> nextCompleted() async {
          final downloads = await manager.stream
              .firstWhere(
                (downloads) => downloads.any(
                  (download) =>
                      download.track.id == 'server-track-1' &&
                      download.status == OfflineDownloadStatus.downloaded,
                ),
              )
              .timeout(const Duration(seconds: 5));
          return downloads.singleWhere(
            (download) => download.track.id == 'server-track-1',
          );
        }

        final firstCompleted = nextCompleted();
        await manager.queueBatch(
          offlineTestDownloadManifest(
            batchId: 'batch-redownload',
            trackId: 'server-track-1',
            byteLength: body.length,
          ),
          label: 'Redownload Album',
        );
        final first = await firstCompleted;

        await manager.removeDownloads([first]);
        expect(manager.downloads, isEmpty);

        final secondCompleted = nextCompleted();
        await manager.queueBatch(
          offlineTestDownloadManifest(
            batchId: 'batch-redownload',
            trackId: 'server-track-1',
            byteLength: body.length,
          ),
          label: 'Redownload Album',
        );
        final second = await secondCompleted;

        expect(downloadRequests, 2);
        expect(second.status, OfflineDownloadStatus.downloaded);
        expect(second.error, isNull);
        expect(await File(second.filePath!).readAsBytes(), body);
      },
    );

    test(
      'manager single-track downloads queue through batch metadata',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_single_batch_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final body = <int>[1, 2, 3, 4];
        var sawBatchRequest = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (request.uri.path == '/api/download/tracks/server-track-1') {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        addTearDown(() => server.close(force: true));

        final connection = SingleBatchTestConnection(
          baseUrl: 'http://127.0.0.1:${server.port}/api',
          manifest: offlineTestDownloadManifest(
            batchId: 'single-batch',
            trackId: 'server-track-1',
            byteLength: body.length,
          ),
          onBatchRequested: () {
            sawBatchRequest = true;
          },
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();
        final completed = manager.stream.firstWhere(
          (downloads) => downloads.any(
            (download) =>
                download.track.id == 'server-track-1' &&
                download.status == OfflineDownloadStatus.downloaded,
          ),
        );

        expect(
          await manager.downloadTrack(offlineTestTrack(id: 'server-track-1')),
          1,
        );
        final downloads = await completed.timeout(const Duration(seconds: 5));
        final downloaded = downloads.singleWhere(
          (download) => download.track.id == 'server-track-1',
        );

        expect(sawBatchRequest, isTrue);
        expect(downloaded.offlineMetadata?.artist.name, 'The Artist');
        expect(downloaded.track.offlineAlbum?.title, 'The Album');
      },
    );

    test('active removal does not resurrect canceled worker state', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_remove_active_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final firstChunkSent = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        try {
          if (request.uri.path == '/api/download/tracks/server-track-1') {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 6;
            request.response.add(<int>[1, 2, 3]);
            await request.response.flush();
            if (!firstChunkSent.isCompleted) {
              firstChunkSent.complete();
            }
            await releaseResponse.future;
            request.response.add(<int>[4, 5, 6]);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } catch (_) {
          if (!firstChunkSent.isCompleted) {
            firstChunkSent.complete();
          }
        }
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final downloading = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloading,
        ),
      );

      await manager.queueBatch(
        offlineTestDownloadManifest(
          batchId: 'batch-active-remove',
          trackId: 'server-track-1',
          byteLength: 6,
        ),
        label: 'Active Remove',
      );

      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      final activeDownloads = await downloading.timeout(
        const Duration(seconds: 5),
      );
      final active = activeDownloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      await manager.removeDownload(active);
      releaseResponse.complete();

      await offlineTestWaitFor(
        () async => (await storage.readDownloads()).isEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(manager.downloads, isEmpty);
      expect(await storage.readDownloads(), isEmpty);
    });

    test('fast resume is not overwritten by active pause cleanup', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_resume_active_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final firstChunkSent = Completer<void>();
      final releaseFirstResponse = Completer<void>();
      var requestCount = 0;
      addTearDown(() {
        if (!releaseFirstResponse.isCompleted) {
          releaseFirstResponse.complete();
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        try {
          if (request.uri.path == '/api/download/tracks/server-track-1') {
            requestCount += 1;
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 6;
            if (requestCount == 1) {
              request.response.add(<int>[1, 2, 3]);
              await request.response.flush();
              if (!firstChunkSent.isCompleted) {
                firstChunkSent.complete();
              }
              await releaseFirstResponse.future;
              request.response.add(<int>[4, 5, 6]);
              await request.response.close();
              return;
            }
            request.response.add(<int>[1, 2, 3, 4, 5, 6]);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } catch (_) {
          if (!firstChunkSent.isCompleted) {
            firstChunkSent.complete();
          }
        }
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final downloading = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloading,
        ),
      );

      await manager.queueBatch(
        offlineTestDownloadManifest(
          batchId: 'batch-active-resume',
          trackId: 'server-track-1',
          byteLength: 6,
        ),
        label: 'Active Resume',
      );

      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      final activeDownloads = await downloading.timeout(
        const Duration(seconds: 5),
      );
      final active = activeDownloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      await manager.pauseDownload(active);
      await manager.resumeDownload(manager.downloads.single);
      releaseFirstResponse.complete();

      await offlineTestWaitFor(
        () async =>
            manager.downloads.single.status == OfflineDownloadStatus.downloaded,
      );
      expect(requestCount, greaterThanOrEqualTo(2));
    });
  });
}

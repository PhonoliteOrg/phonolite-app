part of 'package:phonolite_app/application/app/app_controller.dart';

class _LocalDataCoordinator {
  final AppController _host;
  final _offlineStorageLocationsController = StreamController<OfflineStorageLocations>.broadcast();
  OfflineStorageLocations? _offlineStorageLocations;

  _LocalDataCoordinator(this._host);

  Stream<OfflineStorageLocations> get offlineStorageLocationsStream => _offlineStorageLocationsController.stream;

  OfflineStorageLocations? get offlineStorageLocations => _offlineStorageLocations;

  Future<void> resetOfflineData() async {
    try {
      if (_host._playbackState.isLocalPlayback || _host._playbackState.queueSource == PlaybackQueueSource.offline) {
        await _host._stop(requireFileRelease: true);
      }

      await _host._offlineDownloadManager.resetLocalData();
      await _host.loadOfflineStorageLocations();
      await _host.clearMessages();

      _host._pushMessage('Reset all local downloads, metadata, and logs.');
    } catch (err) {
      _host._pushMessage('Failed to reset local data: $err', level: LogLevel.warning);
    }
  }

  Future<void> refreshLibrary() async {
    var offlineRefreshCompleted = true;

    try {
      await _host._offlineDownloadManager.load().timeout(AppController._offlineRefreshTimeout);
      await _host.loadOfflineStorageLocations().timeout(AppController._offlineRefreshTimeout);
    } on TimeoutException {
      offlineRefreshCompleted = false;
      _host._pushMessage('Offline library refresh timed out; continuing with server refresh.', level: LogLevel.warning);
    } catch (err) {
      offlineRefreshCompleted = false;
      _host._pushMessage('Failed to refresh offline library: $err', level: LogLevel.warning);
    }

    if (_host._authState.isAuthorized) {
      await _host.loadArtists(refresh: true);
      _host._pushMessage(
        offlineRefreshCompleted
            ? 'Library refreshed from device and server.'
            : 'Server library refreshed; offline refresh did not complete.',
      );

      return;
    }

    if (offlineRefreshCompleted) {
      _host._pushMessage('Offline library refreshed from device.');
    }
  }

  Future<void> loadOfflineStorageLocations() async {
    try {
      final locations = await _host._offlineStorage.resolveStorageLocations();

      _offlineStorageLocations = locations;

      if (!_offlineStorageLocationsController.isClosed) {
        _offlineStorageLocationsController.add(locations);
      }
    } catch (err) {
      _host._pushMessage('Failed to load offline storage settings: $err');
    }
  }

  Future<void> updateOfflineMetadataDirectory(String? path) async {
    await _updateOfflineStorageLocation(metadataDirectory: path, message: 'Offline metadata storage updated.');
  }

  Future<void> updateOfflineDownloadsDirectory(String? path) async {
    await _updateOfflineStorageLocation(downloadsDirectory: path, message: 'Offline download storage updated.');
  }

  Future<void> resetOfflineMetadataDirectory() async {
    await _host.updateOfflineMetadataDirectory(null);
  }

  Future<void> resetOfflineDownloadsDirectory() async {
    await _host.updateOfflineDownloadsDirectory(null);
  }

  Future<void> _updateOfflineStorageLocation({
    Object? metadataDirectory = _unset,
    Object? downloadsDirectory = _unset,
    required String message,
  }) async {
    try {
      if (metadataDirectory != _unset && downloadsDirectory != _unset) {
        await _host._offlineStorage.updateStorageLocations(
          metadataDirectory: metadataDirectory,
          downloadsDirectory: downloadsDirectory,
        );
      } else if (metadataDirectory != _unset) {
        await _host._offlineStorage.updateStorageLocations(metadataDirectory: metadataDirectory);
      } else if (downloadsDirectory != _unset) {
        await _host._offlineStorage.updateStorageLocations(downloadsDirectory: downloadsDirectory);
      }

      await _host.loadOfflineStorageLocations();
      await _host._offlineDownloadManager.load();

      _host._pushMessage(message);
    } catch (err) {
      _host._pushMessage('Failed to update offline storage: $err');
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LocalDataFacade {
  _LocalDataCoordinator get _localDataCoordinator;

  StreamController<OfflineStorageLocations> get _offlineStorageLocationsController =>
      _localDataCoordinator._offlineStorageLocationsController;

  Stream<OfflineStorageLocations> get offlineStorageLocationsStream =>
      _localDataCoordinator.offlineStorageLocationsStream;

  OfflineStorageLocations? get offlineStorageLocations => _localDataCoordinator.offlineStorageLocations;

  Future<void> resetOfflineData() => _localDataCoordinator.resetOfflineData();

  Future<void> refreshLibrary() => _localDataCoordinator.refreshLibrary();

  Future<void> loadOfflineStorageLocations() => _localDataCoordinator.loadOfflineStorageLocations();

  Future<void> updateOfflineMetadataDirectory(String? path) =>
      _localDataCoordinator.updateOfflineMetadataDirectory(path);

  Future<void> updateOfflineDownloadsDirectory(String? path) =>
      _localDataCoordinator.updateOfflineDownloadsDirectory(path);

  Future<void> resetOfflineMetadataDirectory() => _localDataCoordinator.resetOfflineMetadataDirectory();

  Future<void> resetOfflineDownloadsDirectory() => _localDataCoordinator.resetOfflineDownloadsDirectory();
}

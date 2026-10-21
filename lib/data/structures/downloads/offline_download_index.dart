import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

/// Alias lookup with stable, first-download precedence at both runtime boundaries.
///
/// Aliases are trimmed while indexing. Actor queries keep their exact server key;
/// client queries opt into trimming to preserve the existing facade contract.
class OfflineDownloadIndex {
  final bool trimServerKeys;
  final Map<String, OfflineTrackDownload> _server = {};
  final Map<String, OfflineTrackDownload> _local = {};

  OfflineDownloadIndex(Iterable<OfflineTrackDownload> downloads, {this.trimServerKeys = false}) {
    for (final download in downloads) {
      void addServer(String? id) {
        final value = id?.trim();

        if (value == null || value.isEmpty) {
          return;
        }

        _server.putIfAbsent(_serverKey(download.serverBaseUrl, value), () => download);
      }

      void addLocal(String? id) {
        final value = id?.trim();

        if (value == null || value.isEmpty) {
          return;
        }

        _local.putIfAbsent(value, () => download);
      }

      addServer(download.track.id);
      addServer(download.track.serverTrackId);
      addServer(download.localTrackId);
      addServer(download.track.localId);

      addLocal(download.localTrackId);
      addLocal(download.track.localId);
      addLocal(download.track.id);
      addLocal(download.track.serverTrackId);
    }
  }

  OfflineTrackDownload? findServer(String serverBaseUrl, String trackId) => _server[_serverKey(serverBaseUrl, trackId)];

  OfflineTrackDownload? findLocal(String localTrackId) => _local[localTrackId];

  String _serverKey(String serverBaseUrl, String trackId) =>
      trimServerKeys ? '${serverBaseUrl.trim()}\n${trackId.trim()}' : '$serverBaseUrl\n$trackId';
}

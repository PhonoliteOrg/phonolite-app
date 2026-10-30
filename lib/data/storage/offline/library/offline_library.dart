import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/data/models/collections/local_like_state.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_batch.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion_draft.dart';
import 'package:phonolite_app/data/models/downloads/offline_metadata_repair_request.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/models/preferences/offline_storage_locations.dart';
import 'package:phonolite_app/data/rules/library/track_matching.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/windows_app_storage.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

export 'package:phonolite_app/data/models/collections/local_like_state.dart';
export 'package:phonolite_app/data/models/downloads/download_batch.dart';
export 'package:phonolite_app/data/models/downloads/download_job.dart';
export 'package:phonolite_app/data/models/downloads/download_status.dart';
export 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
export 'package:phonolite_app/data/models/downloads/offline_metadata_repair_request.dart';
export 'package:phonolite_app/data/models/downloads/offline_track_download.dart';

part 'collections/local_favorites_store.dart';
part 'collections/local_playlist_intent_store.dart';
part 'collections/local_playlist_store.dart';
part 'deletion/offline_deletion_store.dart';
part 'deletion/pending_file_delete_store.dart';
part 'downloads/download_job_store.dart';
part 'downloads/download_store.dart';
part 'files/offline_artwork_files.dart';
part 'files/offline_file_layout.dart';
part 'files/offline_storage_relocator.dart';
part 'metadata/offline_metadata_store.dart';
part 'metadata/offline_row_mapper.dart';
part 'metadata/track_source_match_store.dart';
part 'offline_database.dart';
part 'offline_schema.dart';

class OfflineLibraryStorage
    with
        _OfflineStorageRelocatorFacade,
        _OfflineDeletionStoreFacade,
        _OfflineDownloadStoreFacade,
        _OfflineMetadataStoreFacade,
        _OfflineDownloadJobStoreFacade,
        _PendingFileDeleteStoreFacade,
        _LocalFavoritesStoreFacade,
        _LocalPlaylistStoreFacade,
        _LocalPlaylistIntentStoreFacade,
        _TrackSourceMatchStoreFacade,
        _OfflineFileLayoutFacade,
        _OfflineSchemaFacade,
        _OfflineDatabaseFacade,
        _OfflineArtworkFilesFacade,
        _OfflineRowMapperFacade {
  static const String _rootDirName = 'offline';
  static const String _tracksDirName = 'tracks';
  static const String _artDirName = 'art';
  static const String _albumArtDirName = 'albums';
  static const String _artistArtDirName = 'artists';
  static const String _playlistArtDirName = 'playlists';
  static const String _indexFileName = 'offline_library.json';
  static const String _databaseFileName = 'phonolite_offline.sqlite';
  static const String _partialExtension = 'part';
  static const int _schemaVersion = 13;
  static const Object _storageUnset = Object();

  final bool keepDatabaseOpen;
  static final Map<String, Future<Database>> _openDatabases = {};
  final Directory? baseDirectory;
  final Future<Directory> Function()? defaultDirectoryProvider;
  final Directory? metadataDirectory;
  final Directory? downloadsDirectory;
  final OfflineStorageSettingsStorage settingsStorage;

  const OfflineLibraryStorage({
    this.baseDirectory,
    this.keepDatabaseOpen = false,
    this.metadataDirectory,
    this.downloadsDirectory,
    this.settingsStorage = const OfflineStorageSettingsStorage(),
    this.defaultDirectoryProvider,
  });

  @override
  _OfflineRowMapper get _ownerMapper => _OfflineRowMapper();

  @override
  _OfflineArtworkFiles get _ownerArtwork => _OfflineArtworkFiles(this);

  @override
  _OfflineDatabase get _ownerDatabase => _OfflineDatabase(this);

  @override
  _OfflineSchema get _ownerSchema => _OfflineSchema(this);

  @override
  _OfflineFileLayout get _ownerFiles => _OfflineFileLayout(this);

  @override
  _LocalPlaylistStore get _ownerPlaylists => _LocalPlaylistStore(this);

  @override
  _LocalPlaylistIntentStore get _ownerPlaylistIntents => _LocalPlaylistIntentStore(this);

  @override
  _TrackSourceMatchStore get _ownerSourceMatches => _TrackSourceMatchStore(this);

  @override
  _LocalFavoritesStore get _ownerFavorites => _LocalFavoritesStore(this);

  @override
  _PendingFileDeleteStore get _ownerCleanup => _PendingFileDeleteStore(this);

  @override
  _OfflineDownloadJobStore get _ownerJobs => _OfflineDownloadJobStore(this);

  @override
  _OfflineMetadataStore get _ownerMetadata => _OfflineMetadataStore(this);

  @override
  _OfflineDownloadStore get _ownerDownloads => _OfflineDownloadStore(this);

  @override
  _OfflineDeletionStore get _ownerDeletion => _OfflineDeletionStore(this);

  @override
  _OfflineStorageRelocator get _ownerLocations => _OfflineStorageRelocator(this);

  static String extensionFromContentType(String? contentType) =>
      _OfflineFileLayout.extensionFromContentType(contentType);

  static String extensionFromImageContentType(String? contentType) =>
      _OfflineFileLayout.extensionFromImageContentType(contentType);

  static String? extensionFromContentDisposition(String? contentDisposition) =>
      _OfflineFileLayout.extensionFromContentDisposition(contentDisposition);

  static OfflineDownloadStatus _parseStatus(String value) => _OfflineRowMapper._parseStatus(value);

  static DateTime _dateFromMs(int value) => _OfflineRowMapper._dateFromMs(value);

  static String _sourceKey(String serverBaseUrl, String trackId) =>
      _OfflineFileLayout._sourceKey(serverBaseUrl, trackId);

  static String _serverTrackId(OfflineTrackDownload download) => _OfflineFileLayout._serverTrackId(download);

  static String? _pendingDeletePath(String? path) => _PendingFileDeleteStore._pendingDeletePath(path);

  static String? _managedPendingDeletePath(String? path, List<String> deleteRoots) =>
      _PendingFileDeleteStore._managedPendingDeletePath(path, deleteRoots);

  static void _addPendingDeletePath(Set<String> target, String? path, List<String> deleteRoots) =>
      _PendingFileDeleteStore._addPendingDeletePath(target, path, deleteRoots);

  static String _normalizedRootPath(String path) => _PendingFileDeleteStore._normalizedRootPath(path);

  static bool _pathIsUnderAnyRoot(String path, List<String> roots) =>
      _PendingFileDeleteStore._pathIsUnderAnyRoot(path, roots);

  static String _metadataMatchKey(Track track) => _OfflineMetadataStore._metadataMatchKey(track);

  static String _stableId(String value) => _OfflineMetadataStore._stableId(value);

  static String _serverKey(String baseUrl) => _OfflineFileLayout._serverKey(baseUrl);

  static String _safePathToken(String value) => _OfflineFileLayout._safePathToken(value);

  static String _readString(Row row, String key) => _OfflineRowMapper._readString(row, key);

  static String? _readNullableString(Row row, String key) => _OfflineRowMapper._readNullableString(row, key);

  static String? _normalizeOptionalText(String? value) => _OfflineRowMapper._normalizeOptionalText(value);

  static String? _tryReadNullableString(Row row, String key) => _OfflineRowMapper._tryReadNullableString(row, key);

  static int _readInt(Row row, String key) => _OfflineRowMapper._readInt(row, key);

  static int? _readNullableInt(Row row, String key) => _OfflineRowMapper._readNullableInt(row, key);

  static int? _tryReadNullableInt(Row row, String key) => _OfflineRowMapper._tryReadNullableInt(row, key);

  static bool _readBool(Row row, String key) => _OfflineRowMapper._readBool(row, key);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}

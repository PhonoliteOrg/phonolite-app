import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phonolite_app/data/rules/artwork/encoded_artwork.dart';

class StoredArtwork {
  final Uint8List bytes;
  final String? etag;
  final DateTime expiresAt;

  const StoredArtwork({required this.bytes, required this.expiresAt, this.etag});
}

/// Disposable remote images only. Durable offline files are never in this tree.
/// One bounded file holds a small header and encoded bytes; no image is decoded
/// by this storage owner. Cleanup runs as part of writes, never in a service.
class ArtworkDiskCache {
  static const int maximumImageBytes = 16 * 1024 * 1024;
  static const int _maximumHeaderBytes = 1024;
  static const int _maximumInventoryFiles = 10000;
  // Different account loaders can share the disposable directory. Serialize
  // their publications so one owner's directory stamp cannot hide another's.
  static Future<void> _mutations = Future<void>.value();
  static int _mutationRevision = 0;

  final Future<Directory> Function() directory;
  final int maximumBytes;
  final int maximumFiles;
  Future<void> _writes = Future<void>.value();
  bool _closed = false;
  String? _inventoryDirectory;
  DateTime? _inventoryModified;
  int _inventoryRevision = -1;
  Map<String, ({DateTime used, int bytes})>? _inventory;
  int _inventoryBytes = 0;

  ArtworkDiskCache({
    Future<Directory> Function()? directory,
    this.maximumBytes = 256 * 1024 * 1024,
    this.maximumFiles = 10000,
  }) : directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final cache = await getApplicationCacheDirectory();

    return Directory('${cache.path}${Platform.pathSeparator}remote_artwork_v1');
  }

  Future<StoredArtwork?> read(String key) async {
    _validateKey(key);

    if (_closed) {
      return null;
    }

    final root = await directory();
    final file = File('${root.path}${Platform.pathSeparator}$key.art');

    try {
      final length = await file.length();

      if (length < 4 || length > maximumImageBytes + _maximumHeaderBytes + 4) {
        await _discardMalformed(key, length);

        return null;
      }

      final bytes = await file.readAsBytes();
      final headerLength = ByteData.sublistView(bytes, 0, 4).getUint32(0);

      if (headerLength > _maximumHeaderBytes || headerLength + 4 >= bytes.length) {
        await _discardMalformed(key, bytes.length, digest: sha256.convert(bytes).toString());

        return null;
      }

      final header = jsonDecode(utf8.decode(bytes.sublist(4, 4 + headerLength))) as Map<String, dynamic>;
      final imageBytes = Uint8List.sublistView(bytes, 4 + headerLength);

      // Legacy entries have no length/digest. Check JPEG completeness as well
      // so an old truncated image cannot be kept alive by an HTTP 304.
      if ((header['length'] != null && header['length'] != imageBytes.length) ||
          (header['digest'] != null && header['digest'] != sha256.convert(imageBytes).toString()) ||
          !hasCompleteArtworkBytes(imageBytes)) {
        await remove(key, expectedDigest: sha256.convert(imageBytes).toString());
        return null;
      }
      await _touch(file, bytes.length);

      return StoredArtwork(
        bytes: imageBytes,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(header['expires'] as int),
        etag: header['etag'] as String?,
      );
    } on FileSystemException {
      if (_inventory?.containsKey(file.path) ?? false) {
        await _queueMutation(() async => _invalidateInventory());
      }
      return null;
    } on FormatException {
      await remove(key);

      return null;
    } on TypeError {
      await remove(key);

      return null;
    }
  }

  Future<void> write(String key, StoredArtwork artwork) {
    _validateKey(key);

    if (_closed || !hasCompleteArtworkBytes(artwork.bytes) || artwork.bytes.length > maximumImageBytes) {
      return Future<void>.value();
    }

    return _queueMutation(() => _write(key, artwork));
  }

  Future<void> _touch(File file, int bytes) {
    if (_closed) {
      return Future<void>.value();
    }
    return _queueMutation(() async {
      final used = DateTime.now();
      await file.setLastModified(used);
      final entry = _inventory?[file.path];
      if (entry != null && entry.bytes == bytes) {
        _inventory![file.path] = (used: used, bytes: entry.bytes);
        if (_inventoryRevision == _mutationRevision) {
          // Other owners reconcile after a touch; this owner already knows
          // the new access order and can keep its normal write hot path.
          _inventoryRevision = _mutationRevision + 1;
        }
      } else {
        _invalidateInventory();
      }
    });
  }

  Future<void> _discardMalformed(String key, int length, {String? digest}) {
    if (_closed) {
      return Future<void>.value();
    }
    return _queueMutation(() async {
      final root = await directory();
      final file = File('${root.path}${Platform.pathSeparator}$key.art');
      // A read can finish after a newer publication. Do not remove its bytes.
      if (await file.length() != length ||
          (digest != null && sha256.convert(await file.readAsBytes()).toString() != digest)) {
        return;
      }
      await _remove(key, null);
    });
  }

  Future<void> _write(String key, StoredArtwork artwork) async {
    if (_closed) {
      return;
    }

    final root = await directory();
    await root.create(recursive: true);
    await _ensureInventory(root);
    final header = utf8.encode(
      jsonEncode({
        'expires': artwork.expiresAt.millisecondsSinceEpoch,
        'etag': artwork.etag,
        'length': artwork.bytes.length,
        'digest': sha256.convert(artwork.bytes).toString(),
      }),
    );

    if (header.length > _maximumHeaderBytes) {
      return;
    }

    final file = File('${root.path}${Platform.pathSeparator}$key.art');
    final temporary = File('${file.path}.part');

    try {
      final sink = temporary.openWrite();
      final length = ByteData(4)..setUint32(0, header.length);
      try {
        sink.add(length.buffer.asUint8List());
        sink.add(header);
        sink.add(artwork.bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Rename publishes complete bytes. An active old handle owns its bytes;
      // failure to replace a protected file only skips optional persistence.
      await temporary.rename(file.path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        _invalidateInventory();
        return;
      }
      _remember(file.path, used: stat.modified, bytes: stat.size);
      await _prune(root, file);
      await _rememberDirectory(root);
    } on FileSystemException {
      _invalidateInventory();
      rethrow;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> _prune(Directory root, File current) async {
    final inventory = _inventory;
    if (inventory == null) {
      // A pre-existing directory larger than the bounded inventory retains
      // the streaming cleanup path until it is small enough to track.
      await _pruneUntracked(root, current);
      return;
    }
    if (_inventoryBytes <= maximumBytes && inventory.length <= maximumFiles) {
      if (inventory.length > _maximumInventoryFiles) {
        _invalidateInventory();
      }
      return;
    }

    final candidates = <({String path, DateTime used})>[];
    for (final entry in inventory.entries) {
      if (entry.key == current.path) {
        continue;
      }
      candidates.add((path: entry.key, used: entry.value.used));
      if (candidates.length > 128) {
        candidates.sort((a, b) => a.used.compareTo(b.used));
        candidates.removeRange(64, candidates.length);
      }
    }
    candidates.sort((a, b) => a.used.compareTo(b.used));
    for (final candidate in candidates) {
      if (_inventoryBytes <= maximumBytes && inventory.length <= maximumFiles) {
        break;
      }
      try {
        await File(candidate.path).delete();
        if (!identical(inventory, _inventory)) {
          await _pruneUntracked(root, current);
          return;
        }
        _forget(candidate.path);
      } on FileSystemException {
        // Locked files remain charged against the quota. A missing file or an
        // external edit makes reconciliation necessary before admission.
        await _pruneUntracked(root, current);
        return;
      }
    }
    if (_inventoryBytes > maximumBytes || inventory.length > maximumFiles) {
      await current.delete();
      _forget(current.path);
    }
  }

  Future<void> _ensureInventory(Directory root) async {
    // All cache owners share the mutation revision. Directory stamps also
    // detect namespace changes; external in-place edits reconcile when read.
    final modified = (await root.stat()).modified;
    if (_inventory != null &&
        _inventoryDirectory == root.path &&
        _inventoryModified == modified &&
        _inventoryRevision == _mutationRevision) {
      return;
    }
    await _reconcileInventory(root);
  }

  Future<void> _reconcileInventory(Directory root) async {
    Map<String, ({DateTime used, int bytes})>? files = {};
    var total = 0;
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.art')) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      total += stat.size;
      files?[entity.path] = (used: stat.modified, bytes: stat.size);
      if ((files?.length ?? 0) > _maximumInventoryFiles) {
        files = null;
      }
    }
    _inventory = files;
    _inventoryBytes = total;
    _inventoryDirectory = root.path;
    _inventoryModified = (await root.stat()).modified;
    _inventoryRevision = _mutationRevision;
  }

  void _remember(String path, {required DateTime used, required int bytes}) {
    final inventory = _inventory;
    if (inventory == null) {
      return;
    }
    _inventoryBytes -= inventory[path]?.bytes ?? 0;
    inventory[path] = (used: used, bytes: bytes);
    _inventoryBytes += bytes;
    // Reserve one bounded publication slot so a full 10,000-file inventory
    // can evict its oldest entry without rescanning the directory.
    if (inventory.length > _maximumInventoryFiles + 1) {
      _inventory = null;
    }
  }

  void _forget(String path) {
    _inventoryBytes -= _inventory?.remove(path)?.bytes ?? 0;
  }

  void _invalidateInventory() {
    _inventory = null;
    _inventoryModified = null;
  }

  Future<void> _rememberDirectory(Directory root) async {
    if (_inventory != null) {
      _inventoryModified = (await root.stat()).modified;
      // The serialized mutation advances the shared revision on completion.
      _inventoryRevision = _mutationRevision + 1;
    }
  }

  Future<void> _pruneUntracked(Directory root, File current) async {
    _invalidateInventory();
    var total = 0;
    var count = 0;
    final candidates = <({File file, DateTime used, int bytes})>[];

    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.art')) {
        continue;
      }

      final stat = await entity.stat();
      total += stat.size;
      count++;

      if (entity.path != current.path) {
        candidates.add((file: entity, used: stat.modified, bytes: stat.size));

        if (candidates.length > 128) {
          candidates.sort((a, b) => a.used.compareTo(b.used));
          candidates.removeRange(64, candidates.length);
        }
      }
    }

    candidates.sort((a, b) => a.used.compareTo(b.used));

    for (final candidate in candidates) {
      if (total <= maximumBytes && count <= maximumFiles) {
        break;
      }

      try {
        await candidate.file.delete();
        total -= candidate.bytes;
        count--;
      } on FileSystemException {
        // Another reader can hold a file open on Windows. A later write
        // retries cleanup; never remove durable downloaded art to make room.
      }
    }

    if (total > maximumBytes || count > maximumFiles) {
      await current.delete();
    }
  }

  Future<void> remove(String key, {String? expectedDigest}) {
    _validateKey(key);
    if (_closed) {
      return Future<void>.value();
    }
    return _queueMutation(() => _remove(key, expectedDigest));
  }

  Future<void> _remove(String key, String? expectedDigest) async {
    final root = await directory();
    final file = File('${root.path}${Platform.pathSeparator}$key.art');

    try {
      if (expectedDigest != null) {
        final stored = await file.readAsBytes();
        if (stored.length < 4) {
          return;
        }
        final headerLength = ByteData.sublistView(stored, 0, 4).getUint32(0);
        if (headerLength > _maximumHeaderBytes ||
            4 + headerLength >= stored.length ||
            sha256.convert(Uint8List.sublistView(stored, 4 + headerLength)).toString() != expectedDigest) {
          return;
        }
      }
      if (_inventoryDirectory != root.path ||
          _inventoryModified != (await root.stat()).modified ||
          _inventoryRevision != _mutationRevision) {
        _invalidateInventory();
      }
      await file.delete();
      _forget(file.path);
      await _rememberDirectory(root);
    } on FileSystemException {
      _invalidateInventory();
      // Missing/active disposable files do not fail the user's operation.
    }
  }

  Future<void> close() async {
    _closed = true;
    await _writes;
    _invalidateInventory();
  }

  static Future<void> _mutate(Future<void> Function() action) {
    final operation = _mutations.then((_) async {
      try {
        await action();
      } finally {
        _mutationRevision++;
      }
    });
    _mutations = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _queueMutation(Future<void> Function() action) {
    final operation = _writes.then((_) => _mutate(action));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  static void _validateKey(String key) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Expected a content cache digest');
    }
  }
}

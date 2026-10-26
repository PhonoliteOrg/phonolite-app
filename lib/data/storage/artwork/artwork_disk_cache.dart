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

  final Future<Directory> Function() directory;
  final int maximumBytes;
  final int maximumFiles;
  Future<void> _writes = Future<void>.value();
  bool _closed = false;

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
        await file.delete();

        return null;
      }

      final bytes = await file.readAsBytes();
      final headerLength = ByteData.sublistView(bytes, 0, 4).getUint32(0);

      if (headerLength > _maximumHeaderBytes || headerLength + 4 >= bytes.length) {
        await file.delete();

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
      await file.setLastModified(DateTime.now());

      return StoredArtwork(
        bytes: imageBytes,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(header['expires'] as int),
        etag: header['etag'] as String?,
      );
    } on FileSystemException {
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

    final operation = _writes.then((_) => _write(key, artwork));
    _writes = operation.catchError((Object _) {});

    return operation;
  }

  Future<void> _write(String key, StoredArtwork artwork) async {
    if (_closed) {
      return;
    }

    final root = await directory();
    await root.create(recursive: true);
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
      await _prune(root, file);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> _prune(Directory root, File current) async {
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
    final operation = _writes.then((_) => _remove(key, expectedDigest));
    _writes = operation.catchError((Object _) {});
    return operation;
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
      await file.delete();
    } on FileSystemException {
      // Missing/active disposable files do not fail the user's operation.
    }
  }

  Future<void> close() async {
    _closed = true;
    await _writes;
  }

  static void _validateKey(String key) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Expected a content cache digest');
    }
  }
}

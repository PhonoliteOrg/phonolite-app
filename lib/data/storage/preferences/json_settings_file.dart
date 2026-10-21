import 'dart:convert';
import 'dart:io';

import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

/// The file and JSON mechanics shared by preference stores.
///
/// Stores own their schema, defaults, managed-path rules and error policy. This
/// component owns resolution, map encoding, atomic replacement when requested,
/// and serialized read-modify-write updates to one physical file.
class JsonSettingsFile {
  final String name;
  final SettingsFiles files;
  final bool atomicWrites;
  static final Map<String, Future<void>> _updates = {};

  const JsonSettingsFile({required this.name, this.files = const SettingsFiles(), this.atomicWrites = false});

  Future<Map<String, dynamic>?> read({File? source}) async {
    final file = source ?? await files.resolve(name);

    if (!await file.exists()) {
      return null;
    }

    final decoded = jsonDecode(await file.readAsString());

    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> write(Map<String, dynamic> value) async {
    final file = await files.resolve(name, createDirectory: true);

    await _write(file, value);
  }

  /// Preserve unrelated keys and serialize updates across store instances.
  ///
  /// An unreadable previous value is replaced by a new map. The store can
  /// report that recovery through [onReadError]; write failures still propagate
  /// to its own persistence error policy. A failed update never poisons the
  /// queue for later updates.
  Future<void> update(
    void Function(Map<String, dynamic> value) change, {
    void Function(Object error)? onReadError,
  }) async {
    final file = await files.resolve(name, createDirectory: true);
    final path = file.absolute.path;
    final key = Platform.isWindows ? path.toLowerCase() : path;
    final previous = _updates[key] ?? Future<void>.value();

    final next = previous.then((_) async {
      Map<String, dynamic>? value;

      try {
        value = await read(source: file);
      } catch (error) {
        onReadError?.call(error);
      }

      final payload = value ?? <String, dynamic>{};

      change(payload);

      await _write(file, payload);
    });

    // Store a successful tail so callers can handle their own errors without
    // preventing another queued update from running.
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    _updates[key] = tail;

    try {
      await next;
    } finally {
      if (identical(_updates[key], tail)) {
        _updates.remove(key);
      }
    }
  }

  Future<void> _write(File file, Map<String, dynamic> value) async {
    final encoded = jsonEncode(value);

    if (!atomicWrites) {
      await file.writeAsString(encoded);

      return;
    }

    final temporary = File('${file.path}.tmp');

    await temporary.writeAsString(encoded, flush: true);

    await temporary.rename(file.path);
  }
}

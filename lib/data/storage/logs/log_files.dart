import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/storage/preferences/log_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/windows_app_storage.dart';

/// File operations are serialized by AppLogger. No files remain open between
/// writes, and replacing a full file never exposes more than [maxLines] lines.
class LogFiles {
  final Future<Directory> Function()? directoryProvider;
  final int maxLines;
  final LogStorageSettingsStorage? _settingsStorage;
  final Map<String, ListQueue<String>> _lines = {};
  final Set<String> _fileNames = {};
  Directory? _directory;
  bool _directoryIsDefault = true;

  LogFiles({this.maxLines = 3000, LogStorageSettingsStorage? settingsStorage, this.directoryProvider})
    : assert(maxLines > 0),
      _settingsStorage = settingsStorage ?? (directoryProvider == null ? const LogStorageSettingsStorage() : null);

  String? get directoryPath => _directory?.path;

  LogStorageLocation? get storageLocation =>
      _directory == null ? null : LogStorageLocation(directory: _directory!.path, isDefault: _directoryIsDefault);

  Future<void> initialize(Iterable<String> fileNames) async {
    _fileNames.addAll(fileNames);

    final configured = await _settingsStorage?.read();

    _directory = configured == null ? await (directoryProvider?.call() ?? defaultDirectory()) : Directory(configured);
    _directoryIsDefault = configured == null;

    await _directory!.create(recursive: true);

    for (final name in _fileNames) {
      final lines = await _load(name);

      // Normalize existing files and their final newline, and trim oversized
      // files from an earlier version before accepting new entries.
      await _replace(name, lines);
    }
  }

  static Future<Directory> defaultDirectory({
    String? operatingSystem,
    Map<String, String>? environment,
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    final platform = operatingSystem ?? Platform.operatingSystem;
    final variables = environment ?? Platform.environment;

    if (platform == 'windows') {
      final root = WindowsAppStorage.directory(environment: variables);
      if (root != null) {
        return Directory('${root.path}/logs');
      }
    }

    // path_provider supplies an application-specific directory on macOS,
    // Linux, Android and iOS, including sandboxed deployments.
    final support = await (supportDirectoryProvider?.call() ?? getApplicationSupportDirectory());

    return Directory('${support.path}/logs');
  }

  List<String> read(String name) => List.unmodifiable(_lines[name] ?? []);

  /// Called by AppLogger's writer queue so appends and clears cannot race a move.
  Future<List<String>> changeDirectory(String? path) async {
    final warnings = <String>[];
    final trimmed = path?.trim();
    final configured = trimmed == null || trimmed.isEmpty ? null : Directory(trimmed).absolute.path;

    if (configured != null && (_settingsStorage?.usesManagedStoragePaths ?? Platform.isIOS)) {
      throw UnsupportedError('Log storage is managed on this device.');
    }

    final target = configured == null ? await (directoryProvider?.call() ?? defaultDirectory()) : Directory(configured);

    await target.create(recursive: true);

    final currentPath = await _directory!.resolveSymbolicLinks();
    final targetPath = await target.resolveSymbolicLinks();
    final sameDirectory = Platform.isWindows
        ? currentPath.toLowerCase() == targetPath.toLowerCase()
        : currentPath == targetPath;

    if (!sameDirectory) {
      final previous = _directory!;
      final next = LogFiles(directoryProvider: () async => target, maxLines: maxLines);

      await next.initialize(_fileNames);

      for (final name in _fileNames) {
        final source = _lines[name] ?? await _load(name);
        final existing = next.read(name);
        final newest = _mergeRecentLines(existing, source);

        await next._replace(name, newest);
        next._lines[name] = ListQueue.of(newest);
      }

      // Commit the new location before removing only our old category files.
      // A failed copy or preference save leaves the current logs intact.
      await _settingsStorage?.write(configured);
      _lines.clear();
      _lines.addAll(next._lines);

      for (final name in _fileNames) {
        final file = File('${previous.path}/$name');

        try {
          if (await file.exists()) {
            await file.delete();
          }
        } on FileSystemException catch (error) {
          warnings.add('Logs moved, but an old log file could not be removed: $error');
        }
      }
    } else {
      await _settingsStorage?.write(configured);
    }

    _directory = target;
    _directoryIsDefault = configured == null;

    return warnings;
  }

  Future<void> append(Map<String, List<String>> entries) async {
    for (final item in entries.entries) {
      final name = item.key;

      try {
        final lines = _lines[name] ?? await _load(name);
        final mustTrim = lines.length + item.value.length > maxLines;

        for (final line in item.value) {
          lines.add(line);

          if (lines.length > maxLines) {
            lines.removeFirst();
          }
        }

        if (mustTrim) {
          await _replace(name, lines);
        } else if (item.value.isNotEmpty) {
          await _file(name).writeAsString('${item.value.join('\n')}\n', mode: FileMode.append, flush: true);
        }
      } catch (_) {
        // Re-read the committed file after a failed write rather than trusting
        // the in-memory copy of entries that might not have reached disk.
        _lines.remove(name);

        rethrow;
      }
    }
  }

  Future<void> clear() async {
    for (final name in _fileNames) {
      await _replace(name, const <String>[]);
      _lines[name] = ListQueue<String>();
    }
  }

  File _file(String name) => File('${_directory!.path}/$name');

  int _lineTimestamp(String line) {
    final end = line.indexOf(']');

    return end > 1 ? DateTime.tryParse(line.substring(1, end))?.microsecondsSinceEpoch ?? 0 : 0;
  }

  List<String> _mergeRecentLines(List<String> existing, Iterable<String> source) {
    final existingLines = existing.toSet();
    final combined = [...existing, ...source.where((line) => !existingLines.contains(line))];
    final ordered = [
      for (final (index, line) in combined.indexed) (index: index, line: line, time: _lineTimestamp(line)),
    ];

    int compareLines(({int index, String line, int time}) left, ({int index, String line, int time}) right) {
      final byTime = left.time.compareTo(right.time);

      return byTime != 0 ? byTime : left.index.compareTo(right.index);
    }

    ordered.sort(compareLines);

    return ordered.skip(ordered.length > maxLines ? ordered.length - maxLines : 0).map((entry) => entry.line).toList();
  }

  Future<ListQueue<String>> _load(String name) async {
    final lines = ListQueue<String>();
    final file = _file(name);

    if (await file.exists()) {
      await for (final line
          in file.openRead().transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
        lines.add(line);

        if (lines.length > maxLines) {
          lines.removeFirst();
        }
      }
    }

    _lines[name] = lines;

    return lines;
  }

  Future<void> _replace(String name, Iterable<String> lines) async {
    final file = _file(name);
    final temporary = File('${file.path}.tmp');

    await temporary.writeAsString(lines.isEmpty ? '' : '${lines.join('\n')}\n', flush: true);
    await temporary.rename(file.path);
  }
}

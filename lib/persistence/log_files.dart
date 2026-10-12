import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File operations are serialized by AppLogger. No files remain open between
/// writes, and replacing a full file never exposes more than [maxLines] lines.
class LogFiles {
  LogFiles({this.directoryProvider, this.maxLines = 3000})
    : assert(maxLines > 0);

  final Future<Directory> Function()? directoryProvider;
  final int maxLines;
  final Map<String, ListQueue<String>> _lines = {};
  final Set<String> _fileNames = {};
  Directory? _directory;

  String? get directoryPath => _directory?.path;

  static Future<Directory> defaultDirectory({
    String? operatingSystem,
    Map<String, String>? environment,
    Future<Directory> Function()? supportDirectoryProvider,
  }) async {
    final platform = operatingSystem ?? Platform.operatingSystem;
    final variables = environment ?? Platform.environment;
    if (platform == 'windows') {
      final localAppData = variables['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return Directory('$localAppData/Phonolite/logs');
      }
    }
    // path_provider supplies an application-specific directory on macOS,
    // Linux, Android and iOS, including sandboxed deployments.
    final support =
        await (supportDirectoryProvider?.call() ??
            getApplicationSupportDirectory());
    return Directory('${support.path}/logs');
  }

  Future<void> initialize(Iterable<String> fileNames) async {
    _fileNames.addAll(fileNames);
    _directory = await (directoryProvider?.call() ?? defaultDirectory());
    await _directory!.create(recursive: true);
    for (final name in _fileNames) {
      final lines = await _load(name);
      // Normalize existing files and their final newline, and trim oversized
      // files from an earlier version before accepting new entries.
      await _replace(name, lines);
    }
  }

  List<String> read(String name) => List.unmodifiable(_lines[name] ?? []);

  Future<void> append(Map<String, List<String>> entries) async {
    for (final item in entries.entries) {
      final name = item.key;
      try {
        final lines = _lines[name] ?? await _load(name);
        final mustTrim = lines.length + item.value.length > maxLines;
        for (final line in item.value) {
          lines.add(line);
          if (lines.length > maxLines) lines.removeFirst();
        }
        if (mustTrim) {
          await _replace(name, lines);
        } else if (item.value.isNotEmpty) {
          await _file(name).writeAsString(
            '${item.value.join('\n')}\n',
            mode: FileMode.append,
            flush: true,
          );
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

  Future<ListQueue<String>> _load(String name) async {
    final lines = ListQueue<String>();
    final file = _file(name);
    if (await file.exists()) {
      await for (final line
          in file
              .openRead()
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        lines.add(line);
        if (lines.length > maxLines) lines.removeFirst();
      }
    }
    _lines[name] = lines;
    return lines;
  }

  Future<void> _replace(String name, Iterable<String> lines) async {
    final file = _file(name);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      lines.isEmpty ? '' : '${lines.join('\n')}\n',
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

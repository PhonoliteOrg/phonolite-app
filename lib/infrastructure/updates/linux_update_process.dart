import 'dart:convert';
import 'dart:io';

class LinuxUpdateProcess {
  static const coordinator = '/usr/libexec/phonolite-update-coordinator';

  const LinuxUpdateProcess();

  Future<Object?> command(List<String> arguments) async {
    final process = await Process.start(coordinator, arguments);
    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        _bounded(process.stdout),
        _bounded(process.stderr),
      ], eagerError: true).timeout(const Duration(seconds: 30));
      final status = results[0] as int;
      final text = results[1] as String;
      final error = results[2] as String;
      if (status != 0) throw StateError(error.trim().isEmpty ? 'Linux update verification failed.' : error.trim());
      return jsonDecode(text);
    } catch (_) {
      process.kill();
      rethrow;
    }
  }

  Future<Process> coordinate(String directory) =>
      Process.start(coordinator, ['--coordinate', directory], mode: ProcessStartMode.detachedWithStdio);

  /// Returns the identity the installer uses to recognize this app process.
  Future<({int pid, int startTime})> applicationIdentity() async {
    final processId = pid;
    final stat = await File('/proc/$processId/stat').readAsString();
    final startTime = int.parse(stat.substring(stat.lastIndexOf(')') + 2).split(' ')[19]);

    return (pid: processId, startTime: startTime);
  }

  /// Creates a staging directory accessible only to the current user.
  Future<Directory> createPrivateStage() async {
    final stage = await Directory.systemTemp.createTemp('phonolite-update-');

    try {
      await _setMode('700', stage.path);
      return stage;
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  }

  /// Sets owner-only permissions before writing the staged bytes.
  Future<void> writePrivateFile(File file, List<int> bytes) async {
    await file.writeAsBytes(const []);
    await _setMode('600', file.path);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _setMode(String mode, String path) async {
    final result = await Process.run('/usr/bin/chmod', [mode, path]);

    if (result.exitCode != 0) {
      throw FileSystemException('Cannot secure updater staging', path);
    }
  }

  Future<String> _bounded(Stream<List<int>> input) async {
    final bytes = <int>[];
    await for (final chunk in input) {
      if (bytes.length + chunk.length > 1024 * 1024) throw const FormatException('Updater output exceeded its limit.');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}

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

  Future<String> _bounded(Stream<List<int>> input) async {
    final bytes = <int>[];
    await for (final chunk in input) {
      if (bytes.length + chunk.length > 1024 * 1024) throw const FormatException('Updater output exceeded its limit.');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}

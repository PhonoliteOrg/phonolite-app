import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';
import '../../test_driver/live_audio_inspection.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '--help') {
    stdout.writeln(
      'Usage: dart run tools/ui_tests/inspect_live_audio.dart WS_URI [OUTPUT_JSON]',
    );
    return;
  }
  final service = await vmServiceConnectUri(
    arguments.first,
  ).timeout(const Duration(seconds: 15));
  try {
    final result = await inspectLiveAudio(service);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    if (arguments.length > 1) {
      await File(arguments[1]).writeAsString(jsonEncode(result));
    }
  } finally {
    await service.dispose();
  }
}

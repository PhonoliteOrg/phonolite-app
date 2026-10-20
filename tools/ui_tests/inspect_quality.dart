import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '--help') {
    stdout.writeln(
      'Usage: dart run tools/ui_tests/inspect_quality.dart WS_URI [high|medium|low] [sample_ms] [timeout_ms] [send_playback]',
    );
    return;
  }
  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: arguments.first,
  ).timeout(const Duration(seconds: 15));
  try {
    final result = await driver.serviceClient.callServiceExtension(
      'ext.phonolite.inspectQuality',
      isolateId: driver.appIsolate.id,
      args: {
        'quality': arguments.length > 1 ? arguments[1] : 'high',
        'sample_ms': arguments.length > 2 ? arguments[2] : '2000',
        'timeout_ms': arguments.length > 3 ? arguments[3] : '10000',
        'send_playback': arguments.length > 4 ? arguments[4] : 'false',
      },
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.json));
  } finally {
    await driver.close();
  }
}

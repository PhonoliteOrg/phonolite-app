import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

import '../integration_test/audio/audio_report_writer.dart';
import '../integration_test/support/report_channel.dart';
import '../integration_test/support/report_writer.dart';
import '../integration_test/support/timeline_capture.dart';

Future<void> main() => runProfileDriver();

Future<void> runProfileDriver({
  String defaultReportRoot = 'build/ui-profile',
  String suite = 'ui',
  Duration completionTimeout = const Duration(minutes: 16),
}) async {
  final root = Directory(
    Platform.environment['UI_REPORT_DIR'] ?? defaultReportRoot,
  );
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final destination = Directory('${root.path}/$stamp');
  final catalog = <Map<String, dynamic>>[];
  for (final file in Directory(
    'integration_test/catalog',
  ).listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final feature = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    catalog.addAll(
      (feature['interactions'] as List).cast<Map<String, dynamic>>(),
    );
  }
  final data = <String, dynamic>{
    'suite': suite,
    'run_status': 'running',
    'journeys': <Map<String, dynamic>>[],
  };
  Future<void> save() => data['suite'] == 'audio'
      ? writeAudioReport(destination, data)
      : writeUiReport(destination, data, catalog);
  await save();
  await File(
    '${root.path}/latest.txt',
  ).writeAsString('${destination.absolute.path}\n');
  stdout.writeln('Profile report: ${destination.absolute.path}/REPORT.md');

  FlutterDriver? driver;
  StreamSubscription<dynamic>? timelineSubscription;
  UiTimelineCapture? timelineCapture;
  var succeeded = false;
  try {
    driver = await FlutterDriver.connect();
    timelineSubscription = driver.serviceClient.onTimelineEvent.listen((event) {
      for (final entry in event.timelineEvents ?? []) {
        if (entry.json != null) timelineCapture?.add(entry.json!);
      }
    });
    await driver.serviceClient.streamListen('Timeline');
    data['timeline_capture'] = 'timeline_stream_plus_snapshot_tail';
    Response? response;
    Object? terminalError;
    var finished = false;
    // The standard completion response remains authoritative for test success.
    // Separate VM-service messages let the host save each journey before then.
    final completion = driver
        .requestData(null, timeout: completionTimeout)
        .then<void>(
          (value) {
            response = Response.fromJson(value);
            finished = true;
          },
          onError: (Object error) {
            terminalError = error;
            finished = true;
          },
        );
    int? acknowledge;
    var captureTimeline = true;
    String? tracing;
    final captureCpu = Platform.environment['UI_CAPTURE_CPU'] == 'true';
    data['cpu_capture'] = captureCpu;
    int? cpuStart;
    while (!finished) {
      final packet = await driver.serviceClient
          .callServiceExtension(
            UiReportChannel.extensionName,
            isolateId: driver.appIsolate.id,
            args: {if (acknowledge != null) 'acknowledge': '$acknowledge'},
          )
          .timeout(const Duration(seconds: 60));
      final message = packet.json!;
      if (message['event'] == null) continue;
      final event = Map<String, dynamic>.from(message['event'] as Map);
      switch (event['type']) {
        case 'run_metadata':
          data.addAll(Map<String, dynamic>.from(event['metadata'] as Map));
          captureTimeline = data['capture_timeline'] != false;
          await save();
        case 'journey_start':
          if (captureCpu) {
            await driver.serviceClient.clearCpuSamples(driver.appIsolate.id!);
            cpuStart =
                (await driver.serviceClient.getVMTimelineMicros()).timestamp;
          }
          if (captureTimeline) {
            await driver.clearTimeline();
            final clock = await driver.serviceClient.getVMTimelineMicros();
            timelineCapture = UiTimelineCapture(clock.timestamp!);
            await driver.startTracing(
              streams: [
                TimelineStream.dart,
                TimelineStream.embedder,
                TimelineStream.gc,
              ],
            );
            tracing = event['id'] as String;
          }
        case 'journey_result':
          final journey = Map<String, dynamic>.from(event['journey'] as Map);
          final id = journey['id'] as String;
          if (cpuStart != null) {
            final end =
                (await driver.serviceClient.getVMTimelineMicros()).timestamp!;
            final samples = await driver.serviceClient.getCpuSamples(
              driver.appIsolate.id!,
              cpuStart,
              end - cpuStart,
            );
            await File(
              '${destination.path}/$id.cpu.json',
            ).writeAsString(jsonEncode(samples.toJson()));
            cpuStart = null;
          }
          if (tracing != null) {
            if (tracing != id) throw StateError('Mismatched journey trace');
            final clock = await driver.serviceClient.getVMTimelineMicros();
            // Download/parse on the Mac. Never accumulate full VM traces in
            // the phone's Dart heap or in the SDK's final response payload.
            await driver.serviceClient.setVMTimelineFlags([]);
            final timeline = await driver.serviceClient.getVMTimeline();
            for (final entry in timeline.traceEvents ?? []) {
              if (entry.json != null) timelineCapture!.add(entry.json!);
            }
            // Drain stream messages already in flight after the snapshot RPC.
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await writeUiTimeline(
              destination,
              id,
              timelineCapture!.finish(clock.timestamp!),
            );
            timelineCapture = null;
            tracing = null;
          }
          (data['journeys'] as List).add(journey);
          await save();
          stdout.writeln('Saved $id (${journey['status']})');
        default:
          throw FormatException('Unknown UI report event');
      }
      // The phone releases each result only after its files are saved.
      acknowledge = message['sequence'] as int;
    }
    await completion;
    if (terminalError != null) throw terminalError!;
    if (response == null) throw StateError('No integration-test response');
    data.addAll({...?response!.data}..remove('journeys'));
    succeeded = response!.allTestsPassed;
    data['run_status'] = succeeded ? 'passed' : 'failed';
    if (!succeeded) stderr.writeln(response!.formattedFailureDetails);
  } catch (error) {
    data['run_status'] = 'interrupted';
    data['interruption'] = 'Driver disconnected or could not finish the run.';
    stderr.writeln('Profile interrupted: $error');
  } finally {
    await save();
    await timelineSubscription?.cancel();
    try {
      await driver?.serviceClient.setVMTimelineFlags([]);
      await driver?.close();
    } catch (_) {
      // A terminated app can no longer close the service cleanly.
    }
  }
  stdout.writeln('Profile report: ${destination.absolute.path}/REPORT.md');
  exit(succeeded ? 0 : 1);
}

import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/android_channel_output.dart';

Future<List<OutputDevice>> listAndroidAudioDevices() async {
  final devices = <OutputDevice>[];
  final seen = <int>{kDefaultOutputDeviceId};

  try {
    final result = await androidAudioOutputChannel.invokeMethod<List<dynamic>>('listOutputDevices');

    for (final item in result ?? const []) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] as num?)?.toInt();
      final name = map['name']?.toString().trim();

      if (id == null || name == null || name.isEmpty || !seen.add(id)) {
        continue;
      }

      devices.add(OutputDevice(id: id, name: name));
    }
  } catch (_) {
    // Device discovery is optional; the system-default output remains usable.
  }

  return devices;
}

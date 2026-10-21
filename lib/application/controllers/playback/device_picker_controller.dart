import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';

class DevicePickerController extends FeatureController {
  final Future<List<OutputDevice>> Function(bool refresh) fetchDevices;
  late final _requests = createRequestGeneration();
  List<OutputDevice> _devices = const [];
  bool _loading = true;
  String? _error;

  DevicePickerController(this.fetchDevices);

  List<OutputDevice> get devices => List.unmodifiable(_devices);

  bool get loading => _loading;

  String? get error => _error;

  Future<void> loadDevices({bool refresh = false}) async {
    final request = _requests.advance();

    void beginLoading() {
      _loading = true;
      _error = null;
    }

    update(beginLoading);

    try {
      final devices = await fetchDevices(refresh);

      if (!_requests.isCurrent(request)) {
        return;
      }

      void publishDevices() {
        _devices = List.of(devices);
        _loading = false;
      }

      update(publishDevices);
    } catch (err) {
      if (!_requests.isCurrent(request)) {
        return;
      }

      void publishFailure() {
        _error = err.toString();
        _loading = false;
      }

      update(publishFailure);
    }
  }
}

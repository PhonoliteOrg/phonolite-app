import 'package:connectivity_plus/connectivity_plus.dart';

abstract class ConnectivitySignalSource {
  const ConnectivitySignalSource();

  Stream<bool> get availabilityStream;
  Future<bool> hasConnectivity();
}

class ConnectivityPlusSignalSource extends ConnectivitySignalSource {
  ConnectivityPlusSignalSource({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> get availabilityStream => _connectivity.onConnectivityChanged
      .map(_hasUsableConnectivity)
      .distinct();

  @override
  Future<bool> hasConnectivity() async {
    return _hasUsableConnectivity(await _connectivity.checkConnectivity());
  }

  static bool _hasUsableConnectivity(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }
}

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:phonolite_app/data/models/network/network_connectivity.dart';

abstract class ConnectivitySignalSource {
  const ConnectivitySignalSource();

  Stream<NetworkConnectivity> get stateStream;

  Future<NetworkConnectivity> currentState();
}

class ConnectivityPlusSignalSource extends ConnectivitySignalSource {
  final Connectivity _connectivity;

  ConnectivityPlusSignalSource({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  @override
  Stream<NetworkConnectivity> get stateStream => _connectivity.onConnectivityChanged.map(_decode).distinct();

  @override
  Future<NetworkConnectivity> currentState() async {
    return _decode(await _connectivity.checkConnectivity());
  }

  static NetworkConnectivity _decode(List<ConnectivityResult> results) =>
      NetworkConnectivity(results.map(_transport).nonNulls);

  static NetworkTransport? _transport(ConnectivityResult result) => switch (result) {
    ConnectivityResult.wifi => NetworkTransport.wifi,
    ConnectivityResult.mobile => NetworkTransport.cellular,
    ConnectivityResult.ethernet => NetworkTransport.ethernet,
    ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
    ConnectivityResult.vpn => NetworkTransport.vpn,
    ConnectivityResult.none => null,
    _ => NetworkTransport.other,
  };
}

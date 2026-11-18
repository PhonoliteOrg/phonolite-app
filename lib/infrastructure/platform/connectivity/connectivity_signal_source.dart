import 'dart:async';

import 'package:phonolite_app/data/models/network/network_connectivity.dart';

abstract class ConnectivitySignalSource {
  const ConnectivitySignalSource();

  Stream<NetworkConnectivity> get stateStream;

  Future<NetworkConnectivity> currentState();
}

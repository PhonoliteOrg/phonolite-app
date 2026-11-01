import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/network/network_connectivity.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';

void main() {
  test('Wi-Fi to cellular remains visible when both networks are available', () async {
    final source = ConnectivityPlusSignalSource(
      connectivity: _Connectivity([
        [ConnectivityResult.wifi],
        [ConnectivityResult.wifi],
        [ConnectivityResult.mobile],
        [ConnectivityResult.mobile],
      ]),
    );

    final states = await source.stateStream.toList();

    expect(states, [
      NetworkConnectivity([NetworkTransport.wifi]),
      NetworkConnectivity([NetworkTransport.cellular]),
    ]);
    expect(states.every((state) => state.isAvailable), isTrue);
  });

  test('interface ordering and duplicates do not manufacture network changes', () async {
    final source = ConnectivityPlusSignalSource(
      connectivity: _Connectivity([
        [ConnectivityResult.wifi, ConnectivityResult.vpn],
        [ConnectivityResult.vpn, ConnectivityResult.wifi, ConnectivityResult.wifi],
        [ConnectivityResult.none],
      ]),
    );

    expect(await source.stateStream.toList(), [
      NetworkConnectivity([NetworkTransport.wifi, NetworkTransport.vpn]),
      const NetworkConnectivity.offline(),
    ]);
  });

  test('initial connectivity uses the same interface decoding as streamed changes', () async {
    final source = ConnectivityPlusSignalSource(
      connectivity: _Connectivity([
        [ConnectivityResult.mobile],
      ]),
    );

    expect(await source.currentState(), NetworkConnectivity([NetworkTransport.cellular]));
  });

  test('network interface snapshots are immutable unordered values', () {
    final interfaces = {NetworkTransport.wifi, NetworkTransport.vpn};
    final snapshot = NetworkConnectivity(interfaces);
    final equivalent = NetworkConnectivity([NetworkTransport.vpn, NetworkTransport.wifi]);
    interfaces.clear();

    expect(snapshot.isAvailable, isTrue);
    expect(snapshot, equivalent);
    expect(snapshot.hashCode, equivalent.hashCode);
    expect(() => snapshot.transports.clear(), throwsUnsupportedError);
    expect(const NetworkConnectivity.offline().isAvailable, isFalse);
  });
}

class _Connectivity implements Connectivity {
  final List<List<ConnectivityResult>> states;

  _Connectivity(this.states);

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.fromIterable(states);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => states.first;
}

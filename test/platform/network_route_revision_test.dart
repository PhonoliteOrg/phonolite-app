import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/network/network_connectivity.dart';
import 'package:phonolite_app/infrastructure/platform/connectivity/connectivity_signal_source.dart';

void main() {
  test('route revisions distinguish Wi-Fi paths without inventing a new transport', () async {
    final connectivity = _Connectivity();
    final routes = StreamController<int>();
    final source = ConnectivityPlusSignalSource(connectivity: connectivity, routeRevisions: routes.stream);
    final states = <NetworkConnectivity>[];
    final subscription = source.stateStream.listen(states.add);
    connectivity.changes.add([ConnectivityResult.wifi]);
    await _drain();
    routes.add(1);
    await _drain();
    expect(states.map((state) => state.routeRevision), [0], reason: 'the first native snapshot is a baseline');
    routes.add(1);
    routes.add(2);
    routes.add(3);
    await _drain();

    expect(states.map((state) => state.routeRevision), [0, 1, 2]);
    expect(states.every((state) => state.transports.single == NetworkTransport.wifi), isTrue);
    expect(await source.currentState(), states.last);
    await subscription.cancel();
    await connectivity.changes.close();
    await routes.close();
  });

  test('an unavailable native monitor leaves plugin updates alive and cancels both owners', () async {
    var routeCancelled = false;
    final connectivity = _Connectivity();
    final routes = StreamController<int>(onCancel: () => routeCancelled = true);
    final source = ConnectivityPlusSignalSource(connectivity: connectivity, routeRevisions: routes.stream);
    final states = <NetworkConnectivity>[];
    final subscription = source.stateStream.listen(states.add);
    routes.addError(MissingPluginException('older host'));
    await _drain();
    connectivity.changes.add([ConnectivityResult.wifi]);
    connectivity.changes.add([ConnectivityResult.mobile]);
    await _drain();

    expect(states.map((state) => state.transports.single), [NetworkTransport.wifi, NetworkTransport.cellular]);
    expect(routeCancelled, isTrue);
    await subscription.cancel();
    expect(connectivity.cancelled, isTrue);
    await connectivity.changes.close();
    await routes.close();
  });

  test('listener cancellation releases the native revision stream', () async {
    var routeCancelled = false;
    final connectivity = _Connectivity();
    final routes = StreamController<int>(onCancel: () => routeCancelled = true);
    final source = ConnectivityPlusSignalSource(connectivity: connectivity, routeRevisions: routes.stream);
    final subscription = source.stateStream.listen((_) {});
    await subscription.cancel();

    expect(routeCancelled, isTrue);
    expect(connectivity.cancelled, isTrue);
    await connectivity.changes.close();
    await routes.close();
  });

  test('network snapshot equality includes route revision and keeps transports unordered', () {
    final first = NetworkConnectivity([NetworkTransport.wifi, NetworkTransport.vpn], routeRevision: 2);
    final equivalent = NetworkConnectivity([NetworkTransport.vpn, NetworkTransport.wifi], routeRevision: 2);
    final replacement = NetworkConnectivity([NetworkTransport.wifi, NetworkTransport.vpn], routeRevision: 3);

    expect(first, equivalent);
    expect(first.hashCode, equivalent.hashCode);
    expect(first, isNot(replacement));
  });
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

class _Connectivity implements Connectivity {
  late final changes = StreamController<List<ConnectivityResult>>(onCancel: () => cancelled = true);
  bool cancelled = false;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => changes.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];
}

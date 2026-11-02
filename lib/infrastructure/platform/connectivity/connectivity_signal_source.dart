import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/network/network_connectivity.dart';

abstract class ConnectivitySignalSource {
  const ConnectivitySignalSource();

  Stream<NetworkConnectivity> get stateStream;

  Future<NetworkConnectivity> currentState();
}

class ConnectivityPlusSignalSource extends ConnectivitySignalSource {
  static const _routesChannel = EventChannel('com.phonoliteorg.phonolite_app/network_routes');

  final Connectivity _connectivity;
  final Stream<int> _routeRevisions;

  int _routeRevision = 0;
  int? _lastNativeRevision;

  ConnectivityPlusSignalSource({Connectivity? connectivity, Stream<int>? routeRevisions})
    : _connectivity = connectivity ?? Connectivity(),
      _routeRevisions = routeRevisions ?? (connectivity == null ? _nativeRouteRevisions() : const Stream.empty());

  @override
  Stream<NetworkConnectivity> get stateStream => Stream<NetworkConnectivity>.multi((events) {
    List<ConnectivityResult>? latestInterfaces;
    var interfacesDone = false;
    var routesDone = false;
    var cancelled = false;
    StreamSubscription<int>? routes;

    void closeWhenDone() {
      if (interfacesDone && routesDone && !cancelled) {
        events.close();
      }
    }

    final interfaces = _connectivity.onConnectivityChanged.listen(
      (results) {
        latestInterfaces = results;
        events.add(_decode(results));
      },
      onError: events.addError,
      onDone: () {
        interfacesDone = true;
        closeWhenDone();
      },
    );
    routes = _routeRevisions.listen(
      (revision) {
        if (revision < 0 || cancelled) {
          return;
        }

        if (_lastNativeRevision != revision) {
          if (_lastNativeRevision != null) {
            _routeRevision++;
          }

          _lastNativeRevision = revision;
        }

        final results = latestInterfaces;

        if (results != null) {
          events.add(_decode(results));
        }
      },
      onError: (Object error, StackTrace stack) {
        // Older hosts and unsupported platforms retain the plugin/progress
        // fallback. A missing native monitor must not terminate connectivity.
        routesDone = true;
        unawaited(routes?.cancel());
        closeWhenDone();
      },
      onDone: () {
        routesDone = true;
        closeWhenDone();
      },
    );
    events.onPause = () {
      interfaces.pause();
      routes?.pause();
    };
    events.onResume = () {
      interfaces.resume();
      routes?.resume();
    };
    events.onCancel = () async {
      cancelled = true;
      await Future.wait([interfaces.cancel(), if (routes != null) routes.cancel()]);
    };
  }).distinct();

  @override
  Future<NetworkConnectivity> currentState() async {
    return _decode(await _connectivity.checkConnectivity());
  }

  NetworkConnectivity _decode(List<ConnectivityResult> results) =>
      NetworkConnectivity(results.map(_transport).nonNulls, routeRevision: _routeRevision);

  static Stream<int> _nativeRouteRevisions() {
    if (kIsWeb || ![TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS].contains(defaultTargetPlatform)) {
      return const Stream.empty();
    }

    return _routesChannel.receiveBroadcastStream().where((value) => value is int).cast<int>();
  }

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

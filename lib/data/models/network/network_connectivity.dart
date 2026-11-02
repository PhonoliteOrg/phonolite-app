enum NetworkTransport { wifi, cellular, ethernet, bluetooth, vpn, other }

/// Reported interfaces, independent of whether the server is reachable.
class NetworkConnectivity {
  final Set<NetworkTransport> transports;
  final int routeRevision;

  NetworkConnectivity(Iterable<NetworkTransport> transports, {this.routeRevision = 0})
    : assert(routeRevision >= 0),
      transports = Set.unmodifiable(transports);

  const NetworkConnectivity.offline({this.routeRevision = 0}) : assert(routeRevision >= 0), transports = const {};

  bool get isAvailable => transports.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkConnectivity &&
          routeRevision == other.routeRevision &&
          transports.length == other.transports.length &&
          transports.every(other.transports.contains);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(transports), routeRevision);
}

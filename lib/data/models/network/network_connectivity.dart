enum NetworkTransport { wifi, cellular, ethernet, bluetooth, vpn, other }

/// Reported interfaces, independent of whether the server is reachable.
class NetworkConnectivity {
  final Set<NetworkTransport> transports;

  NetworkConnectivity(Iterable<NetworkTransport> transports) : transports = Set.unmodifiable(transports);

  const NetworkConnectivity.offline() : transports = const {};

  bool get isAvailable => transports.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkConnectivity &&
          transports.length == other.transports.length &&
          transports.every(other.transports.contains);

  @override
  int get hashCode => Object.hashAllUnordered(transports);
}
